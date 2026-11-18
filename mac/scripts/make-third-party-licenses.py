"""產生 mac/Resources/ThirdPartyLicenses.txt：app 內附的 Python 與各套件的授權條款原文。

用內附那份 Python 跑，列出來的才是真的包進 app 的版本（先 make app 一次，暫存區才有東西）：

    mac/.build/backend-stage/bin/python3 mac/scripts/make-third-party-licenses.py

更新 mac/requirements.lock 之後要重跑，並提交產生的檔案。語音模型不在 app 裡，是使用者另外下載的，
各模型的授權列在 README。
"""
import importlib.metadata as metadata
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE.parent / "Resources" / "ThirdPartyLicenses.txt"
RULE = "=" * 80
LICENSE_NAMES = ("licen", "copying", "notice")


def declared(md):
    """套件自己宣告的授權：新格式的 License-Expression，舊的 License 欄或分類標籤。"""
    if md.get("License-Expression"):
        return md["License-Expression"]
    text = (md.get("License") or "").strip()
    if text and "\n" not in text and len(text) < 80:
        return text
    labels = [c.split("::")[-1].strip() for c in md.get_all("Classifier", []) if c.startswith("License ::")]
    return "、".join(labels) or "見下方條款"


def license_texts(dist):
    texts = []
    for f in dist.files or []:
        name = Path(str(f)).name.lower()
        if ".dist-info" in str(f) and any(key in name for key in LICENSE_NAMES):
            try:
                texts.append(dist.locate_file(f).read_text(encoding="utf-8", errors="replace").strip())
            except OSError:
                pass
    return texts


def main():
    dists = sorted(metadata.distributions(), key=lambda d: d.metadata["Name"].lower())
    parts = ["九官鳥 Myna 的 app 裡內附了下列開源軟體，以下是各軟體附的授權條款原文。",
             "語音模型不在 app 裡，是另外下載的，授權各自不同，見 README。", ""]
    parts += [RULE, f"Python {sys.version.split()[0]}（python-build-standalone 的可重新定位版本）", RULE, ""]
    cpython = Path(sys.base_prefix) / "lib" / f"python{sys.version_info.major}.{sys.version_info.minor}" / "LICENSE.txt"
    parts.append(cpython.read_text(encoding="utf-8", errors="replace").strip() if cpython.exists()
                 else "Python Software Foundation License，見 https://docs.python.org/3/license.html")
    missing = []
    for dist in dists:
        md = dist.metadata
        texts = license_texts(dist)
        parts += ["", "", RULE, f"{md['Name']} {md['Version']}　授權：{declared(md)}", md.get("Home-page") or "", RULE, ""]
        if texts:
            parts.append("\n\n".join(texts))
        else:
            missing.append(md["Name"])
            parts.append(f"這個套件沒有附授權條款的檔案，宣告的授權是：{declared(md)}")
    OUT.write_text("\n".join(parts).rstrip() + "\n", encoding="utf-8")
    print(f"{OUT.name}：{len(dists)} 個套件，{OUT.stat().st_size // 1024} KB" +
          (f"；沒附條款檔的：{'、'.join(missing)}" if missing else ""))


if __name__ == "__main__":
    main()
