"""ComfyUI nodes that feed a chat's photos to FLUX.2 Klein as references.

Open WebUI fills a fixed list of image slots, but people attach one, two or three
photos. An empty slot here is simply skipped, where a normal LoadImage node would
fail. Phone photos are turned upright using their EXIF rotation.
"""

import math

import comfy.utils
import folder_paths
import node_helpers
import numpy as np
import torch
from PIL import Image, ImageOps


class GillisOptionalImage:
    CATEGORY = "image"
    FUNCTION = "load"
    RETURN_TYPES = ("IMAGE",)

    @classmethod
    def INPUT_TYPES(cls):
        return {"required": {"image": ("STRING", {"default": ""})}}

    def load(self, image):
        if not image:
            return (None,)
        with Image.open(folder_paths.get_annotated_filepath(image)) as source:
            picture = ImageOps.exif_transpose(source).convert("RGB")
        pixels = np.array(picture).astype(np.float32) / 255.0
        return (torch.from_numpy(pixels)[None,],)


def _scale(pixels, megapixels):
    height, width = pixels.shape[1], pixels.shape[2]
    factor = math.sqrt(megapixels * 1024 * 1024 / (width * height))
    # The model works in blocks of 16 pixels.
    new_width = max(16, round(width * factor / 16) * 16)
    new_height = max(16, round(height * factor / 16) * 16)
    resized = comfy.utils.common_upscale(pixels.movedim(-1, 1), new_width, new_height, "lanczos", "disabled")
    return resized.movedim(1, -1).clamp(0, 1), new_width, new_height


class GillisReferenceImages:
    CATEGORY = "conditioning"
    FUNCTION = "apply"
    RETURN_TYPES = ("CONDITIONING", "CONDITIONING", "INT", "INT")
    RETURN_NAMES = ("positive", "negative", "width", "height")

    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "positive": ("CONDITIONING",),
                "vae": ("VAE",),
                "megapixels": ("FLOAT", {"default": 1.0, "min": 0.25, "max": 2.0, "step": 0.05}),
            },
            "optional": {
                "image_1": ("IMAGE",),
                "image_2": ("IMAGE",),
                "image_3": ("IMAGE",),
            },
        }

    def apply(self, positive, vae, megapixels, image_1=None, image_2=None, image_3=None):
        images = [image for image in (image_1, image_2, image_3) if image is not None]
        if not images:
            raise ValueError("No images were provided to edit.")

        negative = []
        for tensor, options in positive:
            options = options.copy()
            if options.get("pooled_output") is not None:
                options["pooled_output"] = torch.zeros_like(options["pooled_output"])
            negative.append([torch.zeros_like(tensor), options])

        # The output takes its shape from the first image.
        width, height = 1024, 1024
        for index, image in enumerate(images):
            scaled, scaled_width, scaled_height = _scale(image, megapixels)
            if index == 0:
                width, height = scaled_width, scaled_height
            latent = vae.encode(scaled[:, :, :, :3])
            positive = node_helpers.conditioning_set_values(positive, {"reference_latents": [latent]}, append=True)
            negative = node_helpers.conditioning_set_values(negative, {"reference_latents": [latent]}, append=True)
        return (positive, negative, width, height)


NODE_CLASS_MAPPINGS = {
    "GillisOptionalImage": GillisOptionalImage,
    "GillisReferenceImages": GillisReferenceImages,
}
NODE_DISPLAY_NAME_MAPPINGS = {
    "GillisOptionalImage": "Load Image (optional)",
    "GillisReferenceImages": "Reference Images (FLUX.2)",
}
