#!/usr/bin/env bash
# SOLARA — 3D sokak lambalarını Roblox'a yükle, yeri derle, (istersen) yayınla. Roblox Studio GEREKMEZ.
#
# Ne yapar:
#   1. Open Cloud API anahtarını sorar (gerektiğinde; yazarken ekranda görünmez, dosyaya ya da geçmişe yazılmaz)
#   2. Oyunun sahibi: kullanıcı mı grup mu, numarası
#   3. assets/streetlights/StreetLights.glb'yi Model olarak yükler, asset numarasını
#      src/ServerScriptService/WorldGen/AssetIds.lua'ya yazar   (tools/roblox_upload_asset.py)
#   4. place/SOLARA_StreetLights.rbxlx'i yeniden derler          (tools/build_place.py)
#   5. Sorarsa ve "e" dersen: yeri Open Cloud ile yayınlar (Universe ID + Place ID sorar)
#
# Gerekenler: bash, python3, curl (sadece yayınlama için). Reponun kök klasöründen ya da herhangi bir yerden çalışır.
# API anahtarı izinleri (https://create.roblox.com/dashboard/credentials):
#   - Assets API: asset:read + asset:write        (model yükleme)
#   - Place Publishing: universe-places:write     (yayınlama; zaten kullanıyorsan vardır)
# Anahtar ve model, oyunun sahibi olan hesaba / gruba ait olmalı (yoksa oyun modeli yükleyemez).
#
# Kullanım:   bash solara_streetlights.sh

set -euo pipefail

cd "$(dirname "$0")"

GLB="assets/streetlights/StreetLights.glb"
PLACE_OUT="place/SOLARA_StreetLights.rbxlx"
ASSET_IDS="src/ServerScriptService/WorldGen/AssetIds.lua"

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }   # macOS bash 3.2 uyumlu
say()  { printf '\n\033[1;36m%s\033[0m\n' "$*"; }
fail() { printf '\n\033[1;31mHATA: %s\033[0m\n' "$*" >&2; exit 1; }

# --- python
if command -v python3 >/dev/null 2>&1; then PY=python3
elif command -v python >/dev/null 2>&1; then PY=python
else fail "python3 bulunamadı. Python 3 kur: https://www.python.org/downloads/"; fi

for f in "$GLB" tools/roblox_upload_asset.py tools/build_place.py "$ASSET_IDS"; do
  [ -f "$f" ] || fail "$f yok. Önce repoyu güncelle: git pull"
done

say "SOLARA — 3D sokak lambaları (KMB3D, CC BY 4.0)"

# --- mevcut numara
CURRENT=$(grep -Eo 'StreetLights = [0-9]+' "$ASSET_IDS" | grep -Eo '[0-9]+' || echo 0)
SKIP_UPLOAD=0
if [ "${CURRENT:-0}" != "0" ]; then
  echo "Lambalar zaten yüklenmiş görünüyor (asset $CURRENT)."
  read -rp "Yeniden yüklensin mi? [e/H]: " ans
  case "$(lower "$ans")" in e|evet|y|yes) ;; *) SKIP_UPLOAD=1 ;; esac
fi

# --- API anahtarı (gizli; sadece gerektiğinde bir kez sorulur)
KEY="${ROBLOX_API_KEY:-}"
trap 'KEY=""; unset ROBLOX_API_KEY' EXIT
need_key() {
  if [ -z "$KEY" ]; then
    read -rsp "Open Cloud API anahtarı (yazdığın görünmez, Enter): " KEY
    echo
  fi
  [ -n "$KEY" ] || fail "API anahtarı boş."
}

# --- yükleme
if [ "$SKIP_UPLOAD" = "0" ]; then
  echo
  echo "Oyunun sahibi kim?"
  echo "  1) Benim hesabım (kullanıcı)"
  echo "  2) Bir grup"
  read -rp "Seçim [1/2]: " owner
  case "$owner" in
    1) read -rp "Roblox kullanıcı numaran (profil adresindeki sayı): " OWNER_ID; OWNER_FLAG="--user-id" ;;
    2) read -rp "Grup numarası: " OWNER_ID; OWNER_FLAG="--group-id" ;;
    *) fail "1 ya da 2 yazmalısın." ;;
  esac
  [[ "$OWNER_ID" =~ ^[0-9]+$ ]] || fail "Numara sadece rakam olmalı."
  need_key

  say "Model yükleniyor (birkaç dakika sürebilir)…"
  ROBLOX_API_KEY="$KEY" "$PY" tools/roblox_upload_asset.py "$GLB" "$OWNER_FLAG" "$OWNER_ID" \
      --name "SOLARA Street Lights" \
      --description "Street lights: \"Various Low-Poly Street Lights\" by KMB3D (Sketchfab), CC BY 4.0, modified." \
      --set StreetLights || fail "Yükleme başarısız (yukarıdaki mesaja bak: anahtar izni / sahip numarası)."
fi

NEW_ID=$(grep -Eo 'StreetLights = [0-9]+' "$ASSET_IDS" | grep -Eo '[0-9]+')
[ "$NEW_ID" != "0" ] || fail "AssetIds.lua'da numara yok."
echo "Asset numarası: $NEW_ID"

# --- derleme
say "Yer derleniyor…"
"$PY" tools/build_place.py place/SOLARA_Phase3.rbxlx src "$PLACE_OUT" --patches tools/place_patches.json \
  || fail "Derleme başarısız."
echo "Hazır: $PLACE_OUT"

# --- yayınlama (isteğe bağlı)
echo
read -rp "Şimdi Roblox'ta yayınlansın mı? [e/H]: " pub
case "$(lower "$pub")" in
  e|evet|y|yes)
    command -v curl >/dev/null 2>&1 || fail "curl bulunamadı (yayınlama için gerekli)."
    read -rp "Universe ID (Deneyim numarası): " UNIVERSE_ID
    read -rp "Place ID (Yer numarası): " PLACE_ID
    [[ "$UNIVERSE_ID" =~ ^[0-9]+$ && "$PLACE_ID" =~ ^[0-9]+$ ]] || fail "Numaralar sadece rakam olmalı."
    need_key
    say "Yayınlanıyor…"
    # anahtar başlıkta stdin'den gider (komut satırında / işlem listesinde görünmez)
    RESP=$(printf 'x-api-key: %s\n' "$KEY" | curl -sS -w '\n%{http_code}' -X POST \
      "https://apis.roblox.com/universes/v1/${UNIVERSE_ID}/places/${PLACE_ID}/versions?versionType=Published" \
      -H @- -H "Content-Type: application/xml" --data-binary @"$PLACE_OUT") || fail "İstek gönderilemedi."
    CODE=$(printf '%s' "$RESP" | tail -n1)
    BODY=$(printf '%s' "$RESP" | sed '$d')
    if [ "$CODE" = "200" ]; then
      echo "Yayınlandı: $BODY"
    else
      fail "Yayınlama başarısız (HTTP $CODE): $BODY"
    fi
    ;;
  *) echo "Yayınlanmadı. $PLACE_OUT dosyasını her zamanki yolunla yükleyebilirsin." ;;
esac

say "Bitti."
echo "Oyunda sunucu çıktısında şunu görmelisin:  [StreetLights] 3D lambalar kullanılıyor: ..."
echo "Unutma: oyunun Roblox açıklamasına ekle ->"
echo "  Street lights: \"Various Low-Poly Street Lights\" by KMB3D (Sketchfab), CC BY 4.0, modified."
echo "AssetIds.lua değişti; repoda saklamak için: git add $ASSET_IDS && git commit -m 'Street lights asset id'"
