# -*- coding: utf-8 -*-
"""Pipeline de generation d'assets via l'API Ludo.ai.

Genere (ou reprend un fichier local), convertit et installe une image dans le
projet :
  1. POST https://api.ludo.ai/api/assets/image (synchrone, ~60-90 s, 0.5 credit/image)
  2. Sauvegarde du .webp brut dans markdown/ludo_raw/ (gitignore, retraitement gratuit)
  3. ImageMagick : fond -> transparent (floodfill depuis les bords, PAS un simple
     "couleur = transparent" qui trouerait le sujet), trim du vide, resize <= 600px
  4. Ecriture au chemin cible assets/...

La cle API n'est PAS dans ce fichier (tools/ est committe) : la passer via
--api-key ou la variable d'environnement LUDO_API_KEY (cle disponible dans
markdown/ludoAI_ImageGeneration.md, gitignore).

Exemples :
  python tools/ludo_generate.py --prompt "..." --out assets/waves/pong/ball.png
  python tools/ludo_generate.py --from-file markdown/ludo_raw/ball.webp --out assets/waves/pong/ball.png
  python tools/ludo_generate.py --prompt "..." --out assets/waves/suika/reactor_background.jpg --format jpg
"""

import argparse
import datetime
import glob
import json
import os
import subprocess
import sys
import urllib.request

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
API_URL = "https://api.ludo.ai/api/assets/image"
RAW_DIR = os.path.join(PROJECT_ROOT, "markdown", "ludo_raw")
MANIFEST = os.path.join(PROJECT_ROOT, "markdown", "ludo_manifest.json")

IMAGE_TYPES = ["sprite", "icon", "item-icon", "ui_asset", "sprite-vfx", "texture",
               "tile", "horizontal_tile", "fixed_background", "side_scrolling_background",
               "portrait", "card-art", "splash", "art", "asset", "screenshot", "3d", "generic"]


def log(msg):
    print(msg, flush=True)


def fail(msg):
    log("ERREUR: " + msg)
    sys.exit(1)


def magick(*args):
    cmd = ["magick"] + [str(a) for a in args]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        fail("ImageMagick a echoue: " + " ".join(cmd) + "\n" + res.stderr.strip())
    return res.stdout.strip()


def manifest_load():
    if not os.path.isfile(MANIFEST):
        return []
    with open(MANIFEST, encoding="utf-8") as f:
        return json.load(f)


def manifest_append(entry):
    entries = manifest_load()
    entries.append(entry)
    os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
    with open(MANIFEST, "w", encoding="utf-8") as f:
        json.dump(entries, f, ensure_ascii=False, indent=1)
    log("Manifest mis a jour: %s (%d entrees)" % (MANIFEST, len(entries)))


def raw_key(out_rel):
    """Nom de base unique pour markdown/ludo_raw/, derive du dossier parent +
    stem (PAS le stem seul) : evite les collisions entre sections qui partagent
    un nom de fichier generique (pong/ball.png, breakout/ball.png, ...)."""
    parts = out_rel.replace("\\", "/").split("/")
    stem = os.path.splitext(parts[-1])[0]
    parent = parts[-2] if len(parts) >= 2 else ""
    return (parent + "_" + stem) if parent else stem


def already_done(out_rel, out_abs, key):
    """Retourne la raison si l'asset a deja ete genere, sinon None."""
    if os.path.isfile(out_abs):
        return "le fichier cible existe deja (%s)" % out_rel
    raws = glob.glob(os.path.join(RAW_DIR, key + ".webp")) + \
        glob.glob(os.path.join(RAW_DIR, key + "_v*.webp"))
    if raws:
        return ("une generation a deja ete payee pour ce nom (bruts: %s) — retraiter "
                "gratuitement avec --from-file plutot que regenerer"
                % ", ".join(os.path.basename(r) for r in raws))
    for e in manifest_load():
        if e.get("out") == out_rel:
            return "present dans le manifest (genere le %s)" % e.get("date", "?")
    return None


def call_api(payload, api_key):
    req = urllib.request.Request(
        API_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json",
                 "Authorization": "ApiKey " + api_key},
        method="POST")
    log("Appel API Ludo.ai (synchrone, ~60-90 s)...")
    try:
        with urllib.request.urlopen(req, timeout=300) as resp:
            body = resp.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")[:500]
        fail("HTTP %d sur l'API: %s" % (e.code, detail))
    results = json.loads(body)
    if not isinstance(results, list) or not results or "url" not in results[0]:
        fail("Reponse API inattendue: " + body[:500])
    return [r["url"] for r in results]


def download(url, dest):
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    urllib.request.urlretrieve(url, dest)
    log("Telecharge: %s (%d octets)" % (dest, os.path.getsize(dest)))


def process_image(src, dest, fmt, max_size, fuzz, pad, no_bg, no_trim, jpg_quality):
    """webp brut -> image finale optimisee (png transparent trime, ou jpg opaque)."""
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    w, h = (int(v) for v in magick("identify", "-format", "%w %h", src).split())

    if fmt == "jpg":
        # Backgrounds/tiles opaques : aplatir sur blanc, pas de trim ni transparence.
        magick(src, "-background", "white", "-alpha", "remove", "-alpha", "off",
               "-resize", "%dx%d>" % (max_size, max_size),
               "-quality", str(jpg_quality), dest)
    else:
        args = [src, "-alpha", "set"]
        if not no_bg:
            # Transparence par floodfill depuis 8 points du bord : la couleur de
            # reference est celle DU point (coins + milieux de bords), et seuls les
            # pixels connectes au bord sont vides — un element de meme couleur A
            # L'INTERIEUR du sujet n'est pas touche.
            args += ["-fuzz", "%s%%" % fuzz, "-fill", "none"]
            for x, y in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1),
                         (w // 2, 0), (w // 2, h - 1), (0, h // 2), (w - 1, h // 2)]:
                args += ["-draw", "alpha %d,%d floodfill" % (x, y)]
        if not no_trim:
            args += ["-trim", "+repage"]
            if pad > 0:
                args += ["-bordercolor", "none", "-border", str(pad)]
        args += ["-resize", "%dx%d>" % (max_size, max_size), "PNG32:" + dest]
        magick(*args)

    info = magick("identify", "-format", "%wx%h %b", dest)
    log("Final: %s (%s)" % (dest, info))

    if fmt != "jpg":
        fw, fh = (int(v) for v in info.split()[0].split("x"))
        mean_alpha = float(magick("identify", "-format", "%[fx:mean.a]", dest))
        log("Alpha moyen: %.2f (1.0 = opaque)" % mean_alpha)
        if fw < 8 or fh < 8 or mean_alpha < 0.02:
            log("ATTENTION: resultat quasi vide — le floodfill a probablement mange le sujet.")
            log("  Retraiter avec --fuzz plus bas (ex. 4), ou --no-bg si le sujet touche les bords.")


def main():
    p = argparse.ArgumentParser(description="Genere/convertit/installe un asset Ludo.ai")
    p.add_argument("--prompt", help="Prompt EN de la fiche missing_assets.md")
    p.add_argument("--out",
                   help="Chemin cible relatif projet (ex. assets/waves/pong/ball.png) ; res:// accepte")
    p.add_argument("--image-type", default="sprite", choices=IMAGE_TYPES)
    p.add_argument("--style", default="Anime/Manga", help='Art style Ludo (defaut "Anime/Manga")')
    p.add_argument("--perspective", default="Top-Down")
    p.add_argument("--ratio", default="ar_1_1",
                   help="ar_1_1|default|ar_4_3|ar_16_9|ar_3_4|ar_9_16|ar_19_9|ar_9_19")
    p.add_argument("--n", type=int, default=1, help="Variations (1-8, 0.5 credit chacune)")
    p.add_argument("--format", default="auto", choices=["auto", "png", "jpg"],
                   help="auto = selon l'extension de --out")
    p.add_argument("--max-size", type=int, default=600, help="Dimension max en px (defaut 600)")
    p.add_argument("--fuzz", type=float, default=8, help="Tolerance %% du floodfill (defaut 8)")
    p.add_argument("--pad", type=int, default=2, help="Marge transparente apres trim (defaut 2)")
    p.add_argument("--no-bg", action="store_true", help="Ne pas rendre le fond transparent")
    p.add_argument("--no-trim", action="store_true", help="Ne pas trimmer le vide autour")
    p.add_argument("--jpg-quality", type=int, default=85)
    p.add_argument("--from-file", help="Retraiter un .webp/.png local (aucun appel API)")
    p.add_argument("--api-key", default=os.environ.get("LUDO_API_KEY", ""))
    p.add_argument("--force", action="store_true",
                   help="Regenerer meme si l'asset existe deja (consomme des credits)")
    p.add_argument("--list", action="store_true",
                   help="Afficher le manifest des assets deja generes et sortir")
    args = p.parse_args()

    if args.list:
        entries = manifest_load()
        log("%d asset(s) generes (manifest %s):" % (len(entries), MANIFEST))
        for e in entries:
            log("  [%s] %s  (%s, %s)" % (e.get("date", "?"), e.get("out"),
                                         e.get("action"), e.get("install", "?")))
        return

    if not args.out:
        fail("--out requis (sauf avec --list)")

    out_rel = args.out.replace("res://", "").replace("\\", "/")
    out_abs = os.path.normpath(os.path.join(PROJECT_ROOT, out_rel))
    stem = os.path.splitext(os.path.basename(out_abs))[0]
    key = raw_key(out_rel)
    fmt = args.format
    if fmt == "auto":
        fmt = "jpg" if out_abs.lower().endswith((".jpg", ".jpeg")) else "png"

    if args.from_file:
        raws = [os.path.normpath(os.path.join(PROJECT_ROOT, args.from_file))
                if not os.path.isabs(args.from_file) else args.from_file]
        if not os.path.isfile(raws[0]):
            fail("Fichier introuvable: " + raws[0])
    else:
        if not args.prompt:
            fail("--prompt requis (ou --from-file pour retraiter un fichier local)")
        if not args.api_key:
            fail("Cle API manquante: --api-key ou variable d'environnement LUDO_API_KEY "
                 "(cle dans markdown/ludoAI_ImageGeneration.md)")
        reason = already_done(out_rel, out_abs, key)
        if reason and not args.force:
            fail("ASSET DEJA GENERE — regeneration refusee pour ne pas consommer de credits.\n"
                 "  Raison: %s\n"
                 "  Outrepasser volontairement: --force" % reason)
        if reason and args.force:
            log("AVERTISSEMENT --force: regeneration malgre: %s" % reason)
        payload = {"image_type": args.image_type, "prompt": args.prompt,
                   "art_style": args.style, "perspective": args.perspective,
                   "aspect_ratio": args.ratio, "n": args.n, "augment_prompt": True}
        urls = call_api(payload, args.api_key)
        raws = []
        for i, url in enumerate(urls):
            suffix = "" if len(urls) == 1 else "_v%d" % (i + 1)
            raw = os.path.join(RAW_DIR, key + suffix + ".webp")
            download(url, raw)
            raws.append(raw)

    if len(raws) == 1:
        process_image(raws[0], out_abs, fmt, args.max_size, args.fuzz, args.pad,
                      args.no_bg, args.no_trim, args.jpg_quality)
        install = "installe"
    else:
        # Plusieurs variantes : traiter en _v1.._vN A COTE de la cible, ne rien installer.
        log("%d variantes generees — traiter puis choisir :" % len(raws))
        ext = ".jpg" if fmt == "jpg" else ".png"
        for i, raw in enumerate(raws):
            variant = os.path.join(os.path.dirname(out_abs), "%s_v%d%s" % (stem, i + 1, ext))
            process_image(raw, variant, fmt, args.max_size, args.fuzz, args.pad,
                          args.no_bg, args.no_trim, args.jpg_quality)
        log("Choisir la meilleure variante, la renommer en %s et supprimer les autres."
            % os.path.basename(out_abs))
        install = "variantes a departager"

    manifest_append({
        "date": datetime.datetime.now().strftime("%Y-%m-%d %H:%M"),
        "out": out_rel,
        "action": "reprocess" if args.from_file else "generate",
        "n": len(raws),
        "install": install,
        "raw": [os.path.relpath(r, PROJECT_ROOT).replace("\\", "/") for r in raws],
        "prompt": args.prompt or "",
    })

    log("OK. Ne pas oublier : (1) regarder l'image, (2) cabler le chemin res://%s dans le JSON, "
        "(3) ajouter '- Statut: OK -> res://%s' a la fiche missing_assets.md, "
        "(4) godot --headless --import apres le lot." % (out_rel, out_rel))


if __name__ == "__main__":
    main()
