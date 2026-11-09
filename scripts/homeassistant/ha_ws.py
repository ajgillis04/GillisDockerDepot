# Home Assistant websocket helper, for things the REST API cannot do (entity registry, backup config).
# Run inside the HA container: docker cp it to /tmp/ha_ws.py, then pipe two lines on stdin:
#   line 1 = a long-lived access token, line 2 = a JSON list of websocket commands (without "id").
#   { cat token; echo; echo '[{"type":"backup/config/info"}]'; } | docker exec -i homeassistant python3 /tmp/ha_ws.py
# Prints each result as one JSON line. Keep the token off command lines.
import asyncio, json, sys
import aiohttp

async def main():
    token = sys.stdin.readline().strip()
    cmds = json.loads(sys.stdin.readline())
    async with aiohttp.ClientSession() as s:
        async with s.ws_connect("http://127.0.0.1:8123/api/websocket") as ws:
            await ws.receive_json()
            await ws.send_json({"type": "auth", "access_token": token})
            auth = await ws.receive_json()
            if auth.get("type") != "auth_ok":
                print("auth failed"); return
            for i, cmd in enumerate(cmds, start=1):
                cmd["id"] = i
                await ws.send_json(cmd)
                while True:
                    msg = await ws.receive_json()
                    if msg.get("id") == i and msg.get("type") == "result":
                        print(json.dumps({"cmd": cmd["type"], "success": msg["success"],
                                          "result": msg.get("result"), "error": msg.get("error")}))
                        break

asyncio.run(main())
