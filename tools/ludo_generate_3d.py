#!/usr/bin/env python3
"""Generation d'assets 3D Ludo.ai (image -> GLB texture) — pendant 3D de
tools/ludo_generate.py (spec: markdown/missing_assets_3D.md).

Pipeline:
  1. POST https://api.ludo.ai/api/assets/3d-model  (3 credits/modele)
     payload: image (URL http(s) passee telle quelle, ou fichier local encode
     en base64 data-URI), target_num_faces, texture_size, texture_type,
     request_id.
  2. Si la reponse ne contient pas d'URL .glb: poll
     GET /api/assets/3d-models/results?request_id=... (gratuit) jusqu'a
     obtention (--poll-timeout, defaut 600 s).
  3. Telechargement du GLB vers --out (+ previews eventuelles ignorees).
  4. Entree ajoutee au manifest commun markdown/ludo_manifest.json
     (action "generate3d") — meme anti-doublon que le 2D.

Usage type (racine du projet):
  python tools/ludo_generate_3d.py --api-key <cle> \
    --image assets/waves/asteroid_split/asteroid_xl.png \
    --out assets/ultimate/fragment_l.glb --faces 3000

La cle API n'est JAMAIS ecrite ici (tools/ est versionne) : --api-key ou
env LUDO_API_KEY. Cf. markdown/ludoAI_ImageGeneration.md §1.
"""
import argparse
import base64
import json
import mimetypes
import os
import sys
import time
import urllib.error
import urllib.request

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
API_3D_URL = "https://api.ludo.ai/api/assets/3d-model"
API_RESULTS_URL = "https://api.ludo.ai/api/assets/3d-models/results"
MANIFEST = os.path.join(PROJECT_ROOT, "markdown", "ludo_manifest.json")


def log(msg):
    print(msg, flush=True)


def fail(msg):
    print("ERREUR: " + msg, flush=True)
    sys.exit(1)


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


def already_done(out_rel, out_abs):
    if os.path.isfile(out_abs):
        return "le fichier cible existe deja (%s)" % out_rel
    for e in manifest_load():
        if e.get("out") == out_rel and e.get("action") == "generate3d":
            return "present dans le manifest (genere le %s)" % e.get("date", "?")
    return None


def image_payload(image_arg):
    """URL http(s) telle quelle ; fichier local -> data-URI base64."""
    if image_arg.startswith("http://") or image_arg.startswith("https://"):
        return image_arg
    path = image_arg if os.path.isabs(image_arg) else os.path.join(PROJECT_ROOT, image_arg)
    if not os.path.isfile(path):
        fail("image source introuvable: " + path)
    mime = mimetypes.guess_type(path)[0] or "image/png"
    with open(path, "rb") as f:
        data = base64.b64encode(f.read()).decode("ascii")
    return "data:%s;base64,%s" % (mime, data)


def api_call(url, api_key, payload=None, timeout=300):
    headers = {"Authorization": "ApiKey " + api_key}
    data = None
    if payload is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=headers,
                                 method="POST" if payload is not None else "GET")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = ""
        try:
            body = e.read().decode("utf-8")[:600]
        except Exception:
            pass
        fail("HTTP %d sur %s — %s" % (e.code, url, body))
    except Exception as e:  # timeout, reseau
        fail("appel API %s: %s" % (url, e))


def find_glb_urls(node, found):
    """Cherche recursivement toute URL .glb dans la reponse (parsing defensif:
    le schema exact de Model3DResult n'est pas documente publiquement)."""
    if isinstance(node, dict):
        for v in node.values():
            find_glb_urls(v, found)
    elif isinstance(node, list):
        for v in node:
            find_glb_urls(v, found)
    elif isinstance(node, str):
        if node.startswith("http") and ".glb" in node.split("?")[0].lower():
            found.append(node)


def download(url, dest):
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": "pewpewloot-tools"})
    with urllib.request.urlopen(req, timeout=300) as resp, open(dest, "wb") as f:
        f.write(resp.read())
    log("Telecharge: %s (%d octets)" % (dest, os.path.getsize(dest)))


def main():
    p = argparse.ArgumentParser(description="Ludo.ai image -> modele 3D GLB")
    p.add_argument("--image", help="Image source: chemin local (base64) ou URL http(s)")
    p.add_argument("--out", help="Fichier .glb cible, relatif au projet (ex assets/ultimate/x.glb)")
    p.add_argument("--faces", type=int, default=6000,
                   help="target_num_faces 1000-200000 (defaut 6000 = low-poly)")
    p.add_argument("--texture-size", type=int, default=1024, choices=[1024, 2048])
    p.add_argument("--texture-type", default="simple", choices=["pbr", "simple", "none"])
    p.add_argument("--request-id", default="", help="Defaut: nom du fichier --out")
    p.add_argument("--api-key", default=os.environ.get("LUDO_API_KEY", ""))
    p.add_argument("--poll-interval", type=int, default=12, help="Secondes entre polls")
    p.add_argument("--poll-timeout", type=int, default=600, help="Timeout total du poll (s)")
    p.add_argument("--force", action="store_true", help="Regenerer meme si deja fait")
    p.add_argument("--list", action="store_true", help="Lister les generations 3D du manifest")
    args = p.parse_args()

    if args.list:
        entries = [e for e in manifest_load() if e.get("action") == "generate3d"]
        log("%d modele(s) 3D generes:" % len(entries))
        for e in entries:
            log("  [%s] %s  (source %s, %s faces)" % (
                e.get("date", "?"), e.get("out", "?"), e.get("image_source", "?"), e.get("faces", "?")))
        return

    if not args.image or not args.out:
        fail("--image et --out sont requis (ou --list)")
    if not args.api_key:
        fail("cle API manquante (--api-key ou env LUDO_API_KEY)")
    if not args.out.lower().endswith(".glb"):
        fail("--out doit finir en .glb")

    out_rel = args.out.replace("\\", "/")
    out_abs = out_rel if os.path.isabs(out_rel) else os.path.join(PROJECT_ROOT, out_rel)
    if not args.force:
        reason = already_done(out_rel, out_abs)
        if reason:
            fail("deja fait: %s — utiliser --force pour regenerer (3 credits)" % reason)

    request_id = args.request_id or os.path.splitext(os.path.basename(out_rel))[0]
    payload = {
        "image": image_payload(args.image),
        "target_num_faces": max(1000, min(200000, args.faces)),
        "texture_size": args.texture_size,
        "texture_type": args.texture_type,
        "request_id": request_id,
    }
    log("POST %s (request_id=%s, faces=%d, %s/%d) — 3 credits, generation longue..."
        % (API_3D_URL, request_id, payload["target_num_faces"], args.texture_type, args.texture_size))
    resp = api_call(API_3D_URL, args.api_key, payload)

    urls = []
    find_glb_urls(resp, urls)
    deadline = time.time() + args.poll_timeout
    while not urls and time.time() < deadline:
        log("  ...pas encore de GLB, poll dans %ds (reste %ds)"
            % (args.poll_interval, int(deadline - time.time())))
        time.sleep(args.poll_interval)
        results = api_call(API_RESULTS_URL + "?request_id=" + request_id, args.api_key)
        find_glb_urls(results, urls)
    if not urls:
        fail("aucune URL .glb obtenue apres %ds — verifier credits/statut via GET %s?request_id=%s"
             % (args.poll_timeout, API_RESULTS_URL, request_id))

    download(urls[0], out_abs)
    manifest_append({
        "date": time.strftime("%Y-%m-%d %H:%M"),
        "out": out_rel,
        "action": "generate3d",
        "image_source": args.image.replace("\\", "/"),
        "faces": payload["target_num_faces"],
        "texture_type": args.texture_type,
        "texture_size": args.texture_size,
        "request_id": request_id,
        "install": "depose",
    })
    log("OK. Ne pas oublier: (1) godot --headless --import, (2) cabler le res://%s, "
        "(3) statut dans missing_assets_3D.md." % out_rel)


if __name__ == "__main__":
    main()
