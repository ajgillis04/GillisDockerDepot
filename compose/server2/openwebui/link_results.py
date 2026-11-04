"""
title: Link Search Results
description: Turns pages and videos the model names into real links, using URLs from search results.
version: 1.0.0
"""
# The local models often name a search result and leave out its URL, even when told not to.
# This runs after each answer, so links don't depend on the model. Every URL comes from a
# search_web result in the same chat, so it can't add a link that search didn't return.
import difflib
import json
import re

MAX_VIDEOS = 4
MAX_IMAGES = 5


def normalize(text):
    text = re.sub(r"\s*[-|]\s*youtube\s*$", "", text.strip(), flags=re.I)
    return re.sub(r"[^a-z0-9]+", " ", text.lower()).strip()


def display_title(title):
    title = re.sub(r"\s*[-|]\s*youtube\s*$", "", title.strip(), flags=re.I)
    return re.sub(r"\s*\.\.\.$", "", title).strip()


def search_results(messages):
    """Newest first, so a follow-up prefers its own search."""
    found, seen = [], set()
    for message in reversed(messages):
        for item in message.get("output") or []:
            if item.get("type") != "function_call_output":
                continue
            for part in item.get("output") or []:
                try:
                    rows = json.loads(part.get("text", ""))
                except (AttributeError, TypeError, ValueError):
                    continue
                if not isinstance(rows, list):
                    continue
                for row in rows:
                    if not isinstance(row, dict):
                        continue
                    title, link = row.get("title"), row.get("link")
                    if title and isinstance(link, str) and link.startswith("http") and link not in seen:
                        seen.add(link)
                        found.append({"title": title, "link": link, "norm": normalize(title)})
    return found


def best_match(name, results):
    name = normalize(name)
    if len(name) < 12:
        return None
    best, best_score = None, 0.0
    for result in results:
        title = result["norm"]
        if not title:
            continue
        if name == title:
            score = 1.0
        elif (name in title or title in name) and min(len(name), len(title)) / max(len(name), len(title)) >= 0.5:
            score = 0.95
        else:
            score = difflib.SequenceMatcher(None, name, title).ratio()
        if score > best_score:
            best, best_score = result, score
    return best if best_score >= 0.72 else None


def strip_source_note(line):
    return re.sub(r"\s*\(\s*source:[^)]*\)", "", line, flags=re.I)


def link_line(line, results, used):
    def bold(match):
        inner = match.group(1)
        if "](" in inner:
            return match.group(0)
        tail = ""
        name = inner
        if name.endswith(":"):
            name, tail = name[:-1], ":"
        result = best_match(name, [r for r in results if r["link"] not in used])
        if not result:
            return match.group(0)
        used.add(result["link"])
        return f"**[{name}]({result['link']})**{tail}"

    linked = re.sub(r"\*\*(.+?)\*\*", bold, line)
    if linked == line:
        for result in results:
            title = display_title(result["title"])
            if result["link"] in used or len(title) < 15:
                continue
            position = line.lower().find(title.lower())
            if position >= 0 and "](" not in line:
                used.add(result["link"])
                original = line[position:position + len(title)]
                linked = line[:position] + f"[{original}]({result['link']})" + line[position + len(title):]
                break
    return strip_source_note(linked) if linked != line else line


def add_links(text, results, question=""):
    used = {result["link"] for result in results if result["link"] in text}
    lines, fenced = [], False
    for line in text.split("\n"):
        if line.lstrip().startswith("```"):
            fenced = not fenced
        lines.append(line if fenced else link_line(line, results, used))
    text = "\n".join(lines)

    wants_video = re.search(r"\b(videos?|youtube)\b", f"{question} {text}", flags=re.I)
    has_video_link = re.search(r"https?://(www\.)?(youtube\.com|youtu\.be)/", text)
    if wants_video and not has_video_link:
        videos = [r for r in results if re.match(r"https?://(www\.)?(youtube\.com/watch|youtu\.be/)", r["link"])]
        if videos:
            rows = [f"- [{display_title(r['title'])}]({r['link']})" for r in videos[:MAX_VIDEOS]]
            text = text.rstrip() + "\n\n**Video links**\n" + "\n".join(rows)
    return text


def drop_image_links(text):
    """The image tools already show their picture. A copy from the model is redundant,
    and its address is sometimes made up, which shows as "Image unavailable"."""
    text = re.sub(r"</?image>", "", text)
    text = re.sub(r"!\[[^\]]*\]\([^)\s]*\)", "", text)
    text = re.sub(r"\[[^\]]*\]\([^)\s]*/api/v1/files/[^)\s]*\)", "", text)
    return re.sub(r"\n{3,}", "\n\n", text).strip()


async def earlier_images(chat_id):
    from open_webui.models.chats import Chats

    messages = await Chats.get_messages_map_by_chat_id(chat_id) or {}
    found = []
    for message in sorted(messages.values(), key=lambda m: m.get("timestamp") or 0, reverse=True):
        if message.get("role") != "assistant":
            continue
        for file in message.get("files") or []:
            url = file.get("url") or ""
            if file.get("type") == "image" and url.startswith("/api/v1/files/") and url not in found:
                found.append(url)
    return found[:MAX_IMAGES]


class Filter:
    async def inlet(self, body: dict, __metadata__: dict = None) -> dict:
        # The model mistypes long image IDs from memory, so give it the exact addresses each time.
        try:
            chat_id = (__metadata__ or {}).get("chat_id")
            messages = body.get("messages") or []
            if not chat_id or not messages or messages[-1].get("role") != "user":
                return body
            urls = await earlier_images(chat_id)
            if not urls:
                return body
            note = (
                "\n\n(Images already made in this chat, newest first. To change one, copy its address "
                "exactly into edit_image: " + ", ".join(urls) + ")"
            )
            content = messages[-1].get("content")
            if isinstance(content, str):
                messages[-1]["content"] = content + note
            elif isinstance(content, list):
                content.append({"type": "text", "text": note})
        except Exception as error:
            print(f"link_results inlet: {error}")
        return body

    def outlet(self, body: dict) -> dict:
        messages = body.get("messages") or []
        target = next((m for m in reversed(messages) if m.get("id") == body.get("id")), None)
        if not target or target.get("role") != "assistant":
            return body
        results = search_results(messages)
        question = next((m.get("content") or "" for m in reversed(messages) if m.get("role") == "user"), "")
        # Only image tools. A chart from execute_code needs its link kept.
        made_image = any(
            item.get("type") == "function_call" and item.get("name") in ("generate_image", "edit_image")
            for item in target.get("output") or []
        )
        if not results and not made_image:
            return body

        def fix(text):
            if made_image:
                text = drop_image_links(text)
            return add_links(text, results, question) if results else text

        # The page draws from output when a message has it, so both have to change.
        for item in target.get("output") or []:
            if item.get("type") != "message":
                continue
            for part in item.get("content") or []:
                if part.get("type") == "output_text" and part.get("text"):
                    part["text"] = fix(part["text"])
        if isinstance(target.get("content"), str) and target["content"]:
            target["content"] = fix(target["content"])
        return body
