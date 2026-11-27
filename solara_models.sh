#!/usr/bin/env bash
# SOLARA — bütün 3D modelleri Roblox'a yükle, numaralarını oyun dosyasına yaz, (istersen) yayınla.
# Roblox Studio, Python ya da repo GEREKMEZ: sadece bash ve curl (Termux'ta: pkg install curl).
#
# Gereken dosyalar (hepsi aynı klasörde; varsayılan: telefonun İndirilenler klasörü
# /storage/emulated/0/Download — ya da bu betiğin bulunduğu klasör):
#   SOLARA_Models.rbxlx          oyun dosyası (modellerin numaraları 0, betik doldurur)
#   StreetLights.glb             sokak lambaları   (KMB3D, CC BY 4.0)
#   SOLARA_Cars.glb              12 araba          (cosmo-art)
#   SOLARA_TrafficLights.glb     trafik ışıkları   (Kenney, CC0)
#   SOLARA_Pedestrians.glb       10 yaya           (Microsoft Rocketbox, MIT)
#
# Ne yapar:
#   1. Open Cloud API anahtarını sorar (yazarken görünmez; dosyaya, geçmişe ya da komut satırına yazılmaz)
#   2. Oyunun sahibini sorar (kullanıcı / grup numarası) — modeller oyunun sahibine yüklenmeli
#   3. Her modeli Open Cloud ile "Model" olarak yükler, Roblox'un işlemesini bekler, numarayı alır
#   4. Numaraları SOLARA_Models.rbxlx'in içine yazar (önce yedek: SOLARA_Models.rbxlx.yedek)
#      ve solara_asset_ids.txt dosyasına kaydeder (bu numaraları bana gönder: sonraki derlemelerde kalsınlar)
#   5. İstersen oyunu yayınlar (Universe ID + Place ID sorar)
# Daha önce yüklenmiş bir modelin numarası dosyada varsa onu atlar (istersen yeniden yükler).
#
# API anahtarı izinleri (https://create.roblox.com/dashboard/credentials):
#   - Assets API: asset:read + asset:write          (model yükleme)
#   - Universe Places API / Place Publishing: write  (yayınlama)
#
# Kullanım (Termux):   bash /storage/emulated/0/Download/solara_models.sh
#                      (başka klasör için: bash solara_models.sh /klasör/yolu)
# İlk kez kullanıyorsan Termux'a depolama izni ver: termux-setup-storage

set -uo pipefail

API="https://apis.roblox.com/assets/v1"
PLACE_NAME="SOLARA_Models.rbxlx"
IDS_FILE_NAME="solara_asset_ids.txt"
# anahtar | dosya | Roblox'taki adı | açıklama (atıflar)
MODELS="StreetLights|StreetLights.glb|SOLARA Street Lights|Street lights: Various Low-Poly Street Lights by KMB3D (Sketchfab), CC BY 4.0, modified.
Cars|SOLARA_Cars.glb|SOLARA Cars|Cars: Low Poly Cars by cosmo-art (itch.io), modified.
TrafficLights|SOLARA_TrafficLights.glb|SOLARA Traffic Lights|Traffic lights: City Builder Bits by Kenney, CC0.
Pedestrians|SOLARA_Pedestrians.glb|SOLARA Pedestrians|Pedestrians: Microsoft Rocketbox avatar library, MIT licence, modified."

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
say()  { printf '\n\033[1;36m%s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m%s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m%s\033[0m\n' "$*" >&2; }
fail() { printf '\n\033[1;31mHATA: %s\033[0m\n' "$*" >&2; exit 1; }

KEY=""
trap 'KEY=""' EXIT

command -v curl >/dev/null 2>&1 || fail "curl yok. Termux'ta kur: pkg install curl"

# --- klasör: argüman > İndirilenler > betiğin klasörü
DIR=""
for d in "${1:-}" "/storage/emulated/0/Download" "$HOME/storage/downloads" "$(cd "$(dirname "$0")" && pwd)"; do
  if [ -n "$d" ] && [ -f "$d/$PLACE_NAME" ]; then DIR="$d"; break; fi
done
if [ -z "$DIR" ]; then
  if [ ! -d /storage/emulated/0/Download ]; then
    fail "Telefon depolamasına erişim yok. Önce şunu çalıştır ve izin ver: termux-setup-storage"
  fi
  fail "$PLACE_NAME bulunamadı. Dosyaları İndirilenler'e koy (ya da klasörü yaz: bash solara_models.sh /klasör)."
fi
PLACE="$DIR/$PLACE_NAME"
IDS_FILE="$DIR/$IDS_FILE_NAME"
say "SOLARA — 3D modeller ($DIR)"
grep -q -- "-- @asset Cars:" "$PLACE" || fail "$PLACE_NAME eski bir dosya (model numarası yeri yok). Yeni SOLARA_Models.rbxlx'i indir."

current_id() { # $1 = anahtar
  grep -o -- "$1 = [0-9]*, -- @asset $1:" "$PLACE" | head -n1 | grep -o '= [0-9]*' | grep -o '[0-9]*'
}

# --- durum
TODO=""
echo
echo "Modeller:"
while IFS='|' read -r key file name desc; do
  id="$(current_id "$key")"; id="${id:-0}"
  if [ ! -f "$DIR/$file" ]; then
    printf '  %-14s %-26s DOSYA YOK\n' "$key" "$file"
    if [ "$id" = "0" ]; then fail "$file bulunamadı ($DIR). Paketteki bütün dosyaları aynı klasöre koy."; fi
    continue
  fi
  size=$(wc -c < "$DIR/$file" | tr -d ' ')
  if [ "$id" != "0" ]; then
    printf '  %-14s %-26s %6s KB  zaten yüklü (asset %s)\n' "$key" "$file" "$((size / 1024))" "$id"
  else
    printf '  %-14s %-26s %6s KB  yüklenecek\n' "$key" "$file" "$((size / 1024))"
    TODO="$TODO $key"
  fi
done <<EOF
$MODELS
EOF

if [ -z "$TODO" ]; then
  read -rp "Hepsi zaten yüklü. Yine de hepsi yeniden yüklensin mi? [e/H]: " ans
  case "$(lower "$ans")" in e|evet|y|yes) TODO="StreetLights Cars TrafficLights Pedestrians" ;; esac
fi

need_key() {
  if [ -z "$KEY" ]; then
    read -rsp "Open Cloud API anahtarı (yazdığın görünmez, sonra Enter): " KEY
    echo
  fi
  [ -n "$KEY" ] || fail "API anahtarı boş."
}

json_field() { # $1 = alan adı; stdin = JSON → ilk değer (tırnaksız)
  sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\{0,1\}\([^\",}]*\)\"\{0,1\}.*/\1/p" | head -n1
}

upload() { # $1 anahtar $2 dosya $3 ad $4 açıklama → numarayı yazdırır
  local key="$1" file="$2" name="$3" desc="$4" resp code body op asset tries
  local creator
  if [ "$OWNER_KIND" = "user" ]; then creator="{\"userId\":\"$OWNER_ID\"}"; else creator="{\"groupId\":\"$OWNER_ID\"}"; fi
  local request="{\"assetType\":\"Model\",\"displayName\":\"$name\",\"description\":\"$desc\",\"creationContext\":{\"creator\":$creator}}"
  resp=$(printf 'x-api-key: %s\n' "$KEY" | curl -sS --max-time 600 -w '\n%{http_code}' -X POST "$API/assets" -H @- \
    --form-string "request=$request" \
    -F "fileContent=@$DIR/$file;type=model/gltf-binary;filename=$file") || { warn "  bağlantı hatası"; return 1; }
  code=$(printf '%s' "$resp" | tail -n1)
  body=$(printf '%s' "$resp" | sed '$d')
  if [ "$code" != "200" ]; then
    warn "  Roblox reddetti (HTTP $code): $body"
    case "$code" in
      401|403) warn "  → Anahtarın Assets API (asset:read + asset:write) izni ve doğru hesap/grup için olduğundan emin ol."
               return 2 ;;
      400) warn "  → Sahip numarası ya da dosya kabul edilmedi; mesajı bana gönder." ;;
      413) warn "  → Dosya çok büyük." ;;
    esac
    return 1
  fi
  op=$(printf '%s' "$body" | json_field operationId)
  [ -n "$op" ] || op=$(printf '%s' "$body" | sed -n 's/.*"path"[[:space:]]*:[[:space:]]*"operations\/\([^"]*\)".*/\1/p' | head -n1)
  asset=$(printf '%s' "$body" | json_field assetId)
  tries=0
  while [ -z "$asset" ]; do
    [ -n "$op" ] || { warn "  işlem numarası okunamadı: $body"; return 1; }
    tries=$((tries + 1))
    if [ "$tries" -gt 120 ]; then
      warn "  6 dakikadır işleniyor; sonra yeniden çalıştır (işlem: $op)"
      return 1
    fi
    sleep 3
    printf '.' >&2
    body=$(printf 'x-api-key: %s\n' "$KEY" | curl -sS --max-time 60 "$API/operations/$op" -H @-) || continue
    if printf '%s' "$body" | grep -q '"error"'; then
      echo >&2
      warn "  Roblox işleyemedi: $body"
      return 1
    fi
    if printf '%s' "$body" | grep -q '"done"[[:space:]]*:[[:space:]]*true'; then
      asset=$(printf '%s' "$body" | json_field assetId)
      [ -n "$asset" ] || { echo >&2; warn "  bitti ama numara yok: $body"; return 1; }
    fi
  done
  echo >&2
  printf '%s' "$asset"
}

if [ -n "$TODO" ]; then
  echo
  echo "Oyunun sahibi kim? (modeller oyunun sahibine yüklenmeli, yoksa oyun onları açamaz)"
  echo "  1) Benim hesabım (kullanıcı)"
  echo "  2) Bir grup"
  read -rp "Seçim [1/2]: " owner
  case "$owner" in
    1) OWNER_KIND="user";  read -rp "Roblox kullanıcı numaran (profil adresindeki sayı): " OWNER_ID ;;
    2) OWNER_KIND="group"; read -rp "Grup numarası: " OWNER_ID ;;
    *) fail "1 ya da 2 yazmalısın." ;;
  esac
  [[ "$OWNER_ID" =~ ^[0-9]+$ ]] || fail "Numara sadece rakam olmalı."
  need_key
  cp "$PLACE" "$PLACE.yedek" || fail "Yedek alınamadı."
  FAILED=""
  while IFS='|' read -r key file name desc; do
    case " $TODO " in *" $key "*) ;; *) continue ;; esac
    if [ -n "${AUTH_FAILED:-}" ]; then FAILED="$FAILED $key"; continue; fi
    say "$name yükleniyor ($file)…"
    asset="$(upload "$key" "$file" "$name" "$desc")"
    [ $? -eq 2 ] && AUTH_FAILED=1
    if [ -n "$asset" ] && [[ "$asset" =~ ^[0-9]+$ ]]; then
      sed -i "s/$key = [0-9]*, -- @asset $key:/$key = $asset, -- @asset $key:/" "$PLACE"
      [ "$(current_id "$key")" = "$asset" ] || fail "Numara oyun dosyasına yazılamadı ($key)."
      ok "  tamam: asset $asset"
    else
      FAILED="$FAILED $key"
    fi
  done <<EOF
$MODELS
EOF
fi

# --- numaraları kaydet
{
  echo "SOLARA model numaraları ($(date '+%Y-%m-%d %H:%M'))"
  while IFS='|' read -r key file name desc; do
    echo "$key = $(current_id "$key")"
  done <<EOF
$MODELS
EOF
} > "$IDS_FILE"
echo
cat "$IDS_FILE"
echo "(kaydedildi: $IDS_FILE — bu numaraları bana gönder, sonraki derlemelerde kalsınlar; gizli değiller)"
if [ -n "${FAILED:-}" ]; then
  warn "Yüklenemeyenler:$FAILED — bunlar oyunda eski görünümle kalır. Hata mesajını bana gönder."
fi

# --- yayınlama (isteğe bağlı)
echo
read -rp "Oyun şimdi Roblox'ta yayınlansın mı? [e/H]: " pub
case "$(lower "$pub")" in
  e|evet|y|yes)
    read -rp "Universe ID (Deneyim numarası): " UNIVERSE_ID
    read -rp "Place ID (Yer numarası): " PLACE_ID
    [[ "$UNIVERSE_ID" =~ ^[0-9]+$ && "$PLACE_ID" =~ ^[0-9]+$ ]] || fail "Numaralar sadece rakam olmalı."
    need_key
    say "Yayınlanıyor…"
    RESP=$(printf 'x-api-key: %s\n' "$KEY" | curl -sS --max-time 600 -w '\n%{http_code}' -X POST \
      "https://apis.roblox.com/universes/v1/${UNIVERSE_ID}/places/${PLACE_ID}/versions?versionType=Published" \
      -H @- -H "Content-Type: application/xml" --data-binary @"$PLACE") || fail "İstek gönderilemedi."
    CODE=$(printf '%s' "$RESP" | tail -n1)
    BODY=$(printf '%s' "$RESP" | sed '$d')
    if [ "$CODE" = "200" ]; then ok "Yayınlandı: $BODY"; else fail "Yayınlama başarısız (HTTP $CODE): $BODY"; fi
    ;;
  *) echo "Yayınlanmadı. $PLACE dosyasını her zamanki yolunla yayınlayabilirsin." ;;
esac

say "Bitti."
echo "Oyunda sunucu çıktısında şunları görmelisin:"
echo "  [ModelAssetService] arabalar hazır: ...  / trafik ışıkları hazır / yayalar hazır"
echo "  [StreetLights] 3D lambalar kullanılıyor: ..."
echo "Oyunun Roblox açıklamasına atıfları ekle (OKU_BENI.txt'de hazır metin var)."
