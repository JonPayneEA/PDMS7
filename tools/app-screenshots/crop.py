# Crops the screenshots in shots/ and writes them, reduced to 256 colours, to
# vignettes/app-events/. Run from this folder: python3 crop.py
from PIL import Image

OUT = "../../vignettes/app-events/"


def save(im, name):
    im = im.convert("RGB").quantize(colors=256, method=Image.Quantize.FASTOCTREE,
                                    dither=Image.Dither.NONE)
    im.save(OUT + name, optimize=True)


im = Image.open("shots/app-events-loaded.png")
save(im.crop((0, 0, im.width, 1300)), "events-loaded.png")
for n in ["app-events-moved", "app-events-verdict", "app-events-recession", "app-trial-refit",
          "app-events-refit"]:
    im = Image.open("shots/" + n + ".png")
    if n in ("app-events-moved", "app-events-refit"):
        im = im.crop((0, 0, im.width, 1110))
    save(im, n.replace("app-", "") + ".png")
im = Image.open("shots/app-history.png")
save(im.crop((0, 0, im.width, 665)), "history-path.png")
save(im.crop((0, 1480, im.width, 2150)), "history-candidate.png")
