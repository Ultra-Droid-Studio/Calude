package com.ultradroid.app;

import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.webkit.MimeTypeMap;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.Enumeration;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;
import java.util.zip.ZipOutputStream;
import java.util.List;
import java.util.Locale;

/**
 * Dosya Gezgini'nin gerçek telefon depolamasına erişim katmanı.
 *
 * Yollar "sanal yol" olarak gelir: kök (Dahili depolama) hariç, '/' ile ayrılmış parçalar.
 * Örn. "" = Dahili depolama, "İndirilenler/foo.zip" = /storage/emulated/0/Download/foo.zip.
 * Kökteki Türkçe adlar gerçek klasörlere eşlenir (İndirilenler=Download, Belgeler=Documents, ...).
 */
final class FileOps {

    private static final String[][] ALIAS = {
            {"İndirilenler", "Download"},
            {"Belgeler", "Documents"},
            {"Resimler", "Pictures"},
            {"Müzik", "Music"},
            {"Videolar", "Movies"},
    };
    // Kökte her zaman var olması istenen klasörler (yoksa erişim verilince oluşturulur)
    private static final String[] ENSURE = {"Download", "Documents", "Pictures", "Music", "Movies", "DCIM", "Projeler"};

    private FileOps() { }

    static File root() {
        return Environment.getExternalStorageDirectory();
    }

    private static String toReal(String seg) {
        for (String[] a : ALIAS) if (a[0].equals(seg)) return a[1];
        return seg;
    }

    private static String toDisplay(String real) {
        for (String[] a : ALIAS) if (a[1].equals(real)) return a[0];
        return real;
    }

    /** Sanal yolu gerçek File'a çevirir; kökün dışına çıkamaz. Geçersizse null. */
    static File resolve(String vpath) {
        try {
            File base = root().getCanonicalFile();
            if (vpath == null || vpath.isEmpty()) return base;
            String[] parts = vpath.split("/", -1);
            File f = base;
            for (int i = 0; i < parts.length; i++) {
                String p = parts[i];
                if (p.isEmpty() || p.equals(".") || p.equals("..")) return null;
                f = new File(f, i == 0 ? toReal(p) : p);
            }
            File c = f.getCanonicalFile();
            String bp = base.getPath();
            String cp = c.getPath();
            if (!(cp.equals(bp) || cp.startsWith(bp + File.separator))) return null;
            return f;
        } catch (IOException e) {
            return null;
        }
    }

    private static boolean validName(String n) {
        if (n == null) return false;
        n = n.trim();
        return !n.isEmpty() && !n.equals(".") && !n.equals("..") && n.indexOf('/') < 0 && n.indexOf('\u0000') < 0 && n.length() <= 255;
    }

    private static String ok() { return "{\"ok\":true}"; }

    private static String err(String m) {
        try {
            JSONObject o = new JSONObject();
            o.put("ok", false);
            o.put("err", m);
            return o.toString();
        } catch (Exception e) {
            return "{\"ok\":false,\"err\":\"Hata\"}";
        }
    }

    /** Standart klasörleri (Download, Documents, ... Projeler) oluşturur. */
    static void ensureStd() {
        try {
            File base = root();
            for (String n : ENSURE) {
                File d = new File(base, n);
                if (!d.exists()) d.mkdirs();
            }
        } catch (Throwable ignored) { }
    }

    /** Klasör içeriği: {"ok":true,"items":[{n,d,s,m}]} */
    static String list(String vpath) {
        ZRef zr = zipSplit(vpath);
        if (zr != null) return zipList(zr);
        File dir = resolve(vpath);
        if (dir == null) return err("Geçersiz yol");
        if (!dir.exists()) {
            // standart klasör henüz yoksa oluşturmayı dene
            if (vpath != null && vpath.indexOf('/') < 0) dir.mkdirs();
            if (!dir.exists()) return err("Klasör bulunamadı");
        }
        if (!dir.isDirectory()) return err("Bu bir klasör değil");
        File[] fs = dir.listFiles();
        if (fs == null) return err("Bu klasör okunamadı (izin yok)");
        boolean atRoot = vpath == null || vpath.isEmpty();
        try {
            JSONArray arr = new JSONArray();
            for (File f : fs) {
                String name = f.getName();
                if (name.startsWith(".")) continue;   // gizli dosyalar
                JSONObject o = new JSONObject();
                boolean isDir = f.isDirectory();
                o.put("n", atRoot ? toDisplay(name) : name);
                o.put("d", isDir ? 1 : 0);
                o.put("s", isDir ? 0 : f.length());
                o.put("m", f.lastModified());
                arr.put(o);
            }
            JSONObject res = new JSONObject();
            res.put("ok", true);
            res.put("items", arr);
            return res.toString();
        } catch (Exception e) {
            return err("Liste okunamadı");
        }
    }

    static String mkdir(String vparent, String name) {
        if (!validName(name)) return err("Geçersiz ad");
        if (zipSplit(vparent) != null) return err(ZIP_RO);
        File p = resolve(vparent);
        if (p == null || !p.isDirectory()) return err("Geçersiz klasör");
        File f = new File(p, name.trim());
        if (f.exists()) return err("Bu ad zaten var");
        return f.mkdir() ? ok() : err("Klasör oluşturulamadı");
    }

    static String newFile(String vparent, String name) {
        if (!validName(name)) return err("Geçersiz ad");
        if (zipSplit(vparent) != null) return err(ZIP_RO);
        File p = resolve(vparent);
        if (p == null || !p.isDirectory()) return err("Geçersiz klasör");
        File f = new File(p, name.trim());
        if (f.exists()) return err("Bu ad zaten var");
        try {
            return f.createNewFile() ? ok() : err("Dosya oluşturulamadı");
        } catch (IOException e) {
            return err("Dosya oluşturulamadı");
        }
    }

    static String rename(String vpath, String newName) {
        if (!validName(newName)) return err("Geçersiz ad");
        if (inZipEntry(vpath)) return err(ZIP_RO);
        File f = resolve(vpath);
        if (f == null || !f.exists()) return err("Öğe bulunamadı");
        if (vpath.indexOf('/') < 0) return err("Kökteki klasörler yeniden adlandırılamaz");
        File t = new File(f.getParentFile(), newName.trim());
        if (t.exists()) return err("Bu ad zaten var");
        return f.renameTo(t) ? ok() : err("Yeniden adlandırılamadı");
    }

    private static boolean deleteRec(File f) {
        try {
            // symlink'i takip ederek içeriğini silmemek için
            if (!f.getCanonicalPath().equals(new File(f.getParentFile().getCanonicalFile(), f.getName()).getPath())) {
                return f.delete();
            }
        } catch (IOException ignored) { }
        if (f.isDirectory()) {
            File[] cs = f.listFiles();
            if (cs != null) for (File c : cs) deleteRec(c);
        }
        return f.delete();
    }

    static String delete(String vpath) {
        if (inZipEntry(vpath)) return err(ZIP_RO);
        File f = resolve(vpath);
        if (f == null || !f.exists()) return err("Öğe bulunamadı");
        if (vpath.indexOf('/') < 0) return err("Kökteki klasörler silinemez");
        return deleteRec(f) ? ok() : err("Silinemedi");
    }

    private static String uniqueName(File dir, String name) {
        if (!new File(dir, name).exists()) return name;
        String base = name, ext = "";
        int dot = name.lastIndexOf('.');
        if (dot > 0) { base = name.substring(0, dot); ext = name.substring(dot); }
        int i = 2;
        while (new File(dir, base + " (" + i + ")" + ext).exists()) i++;
        return base + " (" + i + ")" + ext;
    }

    private static boolean copyRec(File src, File dst) {
        try {
            if (src.isDirectory()) {
                if (!dst.mkdirs() && !dst.isDirectory()) return false;
                File[] cs = src.listFiles();
                if (cs == null) return true;
                boolean all = true;
                for (File c : cs) all &= copyRec(c, new File(dst, c.getName()));
                return all;
            }
            InputStream in = new FileInputStream(src);
            try {
                OutputStream out = new FileOutputStream(dst);
                try {
                    byte[] buf = new byte[64 * 1024];
                    int n;
                    while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
                } finally {
                    out.close();
                }
            } finally {
                in.close();
            }
            dst.setLastModified(System.currentTimeMillis());
            return true;
        } catch (IOException e) {
            return false;
        }
    }

    /** Kopyalar ya da taşır. Hedefte aynı ad varsa "ad (2)" olur. */
    static String paste(String vsrc, String vdestDir, boolean move) {
        if (zipSplit(vdestDir) != null) return err("Zip arşivinin içine yapıştırılamaz");
        if (inZipEntry(vsrc)) {                       // zip içinden kopyala = tek öğeyi ayıkla
            if (move) return err("Zip içinden taşınamaz; kopyalayabilirsin");
            return zipCopyEntry(vsrc, vdestDir);
        }
        File src = resolve(vsrc);
        File dir = resolve(vdestDir);
        if (src == null || !src.exists()) return err("Kaynak bulunamadı");
        if (dir == null || !dir.isDirectory()) return err("Hedef klasör geçersiz");
        if (vsrc.indexOf('/') < 0) return err("Kökteki klasörler taşınamaz/kopyalanamaz");
        try {
            String sp = src.getCanonicalPath();
            String dp = dir.getCanonicalPath();
            if (src.isDirectory() && (dp.equals(sp) || dp.startsWith(sp + File.separator))) {
                return err("Klasör kendi içine taşınamaz");
            }
            if (move && src.getParentFile().getCanonicalPath().equals(dp)) return ok();   // aynı yere taşıma
        } catch (IOException e) {
            return err("Yol çözülemedi");
        }
        File dst = new File(dir, uniqueName(dir, src.getName()));
        if (move && src.renameTo(dst)) return ok();
        if (!copyRec(src, dst)) return err("Kopyalanamadı");
        if (move) deleteRec(src);
        return ok();
    }

    /** Son değiştirilen dosyalar (kök altında sığ bir tarama). {"ok":true,"items":[{n,p,s,m}]} p = sanal klasör yolu */
    static String recent(int max) {
        List<Object[]> all = new ArrayList<>();
        scan(root(), "", 0, all);
        java.util.Collections.sort(all, new java.util.Comparator<Object[]>() {
            @Override public int compare(Object[] a, Object[] b) {
                return Long.compare((Long) b[2], (Long) a[2]);
            }
        });
        try {
            JSONArray arr = new JSONArray();
            for (int i = 0; i < all.size() && i < max; i++) {
                Object[] r = all.get(i);
                JSONObject o = new JSONObject();
                o.put("n", r[0]);
                o.put("p", r[1]);
                o.put("m", r[2]);
                o.put("s", r[3]);
                arr.put(o);
            }
            JSONObject res = new JSONObject();
            res.put("ok", true);
            res.put("items", arr);
            return res.toString();
        } catch (Exception e) {
            return err("Okunamadı");
        }
    }

    private static void scan(File dir, String vp, int depth, List<Object[]> out) {
        if (depth > 3 || out.size() > 4000) return;
        File[] fs = dir.listFiles();
        if (fs == null) return;
        for (File f : fs) {
            String name = f.getName();
            if (name.startsWith(".")) continue;
            if (depth == 0 && name.equals("Android")) continue;   // uygulama verileri
            String shown = depth == 0 ? toDisplay(name) : name;
            if (f.isDirectory()) {
                scan(f, vp.isEmpty() ? shown : vp + "/" + shown, depth + 1, out);
            } else {
                out.add(new Object[]{name, vp, f.lastModified(), f.length()});
            }
        }
    }

    private static String mimeOf(File f) {
        String n = f.getName().toLowerCase(Locale.ROOT);
        int dot = n.lastIndexOf('.');
        if (dot < 0) return "*/*";
        String ext = n.substring(dot + 1);
        if (ext.equals("apk")) return "application/vnd.android.package-archive";
        String m = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext);
        return m != null ? m : "*/*";
    }

    /** Dosyayı ilgili Android uygulamasıyla açar (APK ise kurulum ekranı). */
    static String open(Context ctx, String vpath) {
        File f = fileFor(ctx, vpath);
        if (f == null || !f.isFile()) return err("Dosya bulunamadı");
        try {
            Uri uri = androidx.core.content.FileProvider.getUriForFile(ctx, ctx.getPackageName() + ".files", f);
            Intent i = new Intent(Intent.ACTION_VIEW);
            i.setDataAndType(uri, mimeOf(f));
            i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
            ctx.startActivity(i);
            return ok();
        } catch (android.content.ActivityNotFoundException e) {
            return err("Bu dosyayı açabilecek uygulama yok");
        } catch (Throwable t) {
            return err("Açılamadı");
        }
    }

    /** Depolama doluluk bilgisi: {"ok":true,"free":N,"total":N} */
    static String space() {
        try {
            File r = root();
            JSONObject o = new JSONObject();
            o.put("ok", true);
            o.put("free", r.getUsableSpace());
            o.put("total", r.getTotalSpace());
            return o.toString();
        } catch (Exception e) {
            return err("Okunamadı");
        }
    }

    // ------------------------------------------------------------ ZIP: listele, ayıkla, oluştur

    private static final String ZIP_RO = "Zip arşivinin içinde bu işlem yapılamaz";

    /** Sanal yolun içindeki zip dosyası + zip içi yol (inner, '/' ile; "" = zip'in kökü). */
    static final class ZRef {
        final File zip;
        final String inner;
        ZRef(File zip, String inner) { this.zip = zip; this.inner = inner; }
    }

    /** Yolun herhangi bir parçası gerçek bir .zip dosyasıysa ayırır; değilse null. */
    static ZRef zipSplit(String vpath) {
        if (vpath == null || vpath.isEmpty()) return null;
        try {
            File base = root().getCanonicalFile();
            String[] parts = vpath.split("/", -1);
            File f = base;
            for (int i = 0; i < parts.length; i++) {
                String p = parts[i];
                if (p.isEmpty() || p.equals(".") || p.equals("..")) return null;
                f = new File(f, i == 0 ? toReal(p) : p);
                if (f.isFile() && p.toLowerCase(Locale.ROOT).endsWith(".zip")) {
                    StringBuilder sb = new StringBuilder();
                    for (int j = i + 1; j < parts.length; j++) {
                        String q = parts[j];
                        if (q.isEmpty() || q.equals(".") || q.equals("..")) return null;
                        if (sb.length() > 0) sb.append('/');
                        sb.append(q);
                    }
                    String cp = f.getCanonicalPath();
                    if (!cp.startsWith(base.getPath() + File.separator)) return null;
                    return new ZRef(f, sb.toString());
                }
                if (!f.exists()) return null;
            }
        } catch (IOException e) {
            return null;
        }
        return null;
    }

    /** Yol bir zip'in İÇİNDEKİ bir öğeyi mi gösteriyor (zip dosyasının kendisi değil)? */
    private static boolean inZipEntry(String vpath) {
        ZRef z = zipSplit(vpath);
        return z != null && !z.inner.isEmpty();
    }

    /** Sanal yolu gerçek dosyaya çevirir; zip içindeyse girdiyi önbelleğe çıkarıp onu verir. */
    static File fileFor(Context ctx, String vpath) {
        ZRef z = zipSplit(vpath);
        if (z == null) return resolve(vpath);
        if (z.inner.isEmpty()) return z.zip;
        try {
            return zipToCache(ctx, z);
        } catch (Throwable t) {
            return null;
        }
    }

    private static String zipNorm(String name) {
        String n = name.replace('\\', '/');
        while (n.startsWith("/")) n = n.substring(1);
        while (n.endsWith("/")) n = n.substring(0, n.length() - 1);
        return n;
    }

    /** UTF-8 ile açar; ad bozuksa (eski Windows zip'leri) IBM857 / ISO-8859-1 ile yeniden açar. */
    private static ZipFile openZip(File f) throws IOException {
        ZipFile z = null;
        try {
            z = new ZipFile(f);
            Enumeration<? extends ZipEntry> en = z.entries();
            boolean bad = false;
            while (en.hasMoreElements()) {
                if (en.nextElement().getName().indexOf('\uFFFD') >= 0) { bad = true; break; }
            }
            if (!bad) return z;
            z.close();
        } catch (IllegalArgumentException e) {
            if (z != null) try { z.close(); } catch (IOException ignored) { }
        }
        java.nio.charset.Charset cs = java.nio.charset.Charset.isSupported("IBM857")
                ? java.nio.charset.Charset.forName("IBM857") : java.nio.charset.Charset.forName("ISO-8859-1");
        return new ZipFile(f, cs);
    }

    private static String zipListJson(ZRef zr) {
        ZipFile z = null;
        try {
            z = openZip(zr.zip);
            String prefix = zr.inner.isEmpty() ? "" : zr.inner + "/";
            Map<String, JSONObject> out = new LinkedHashMap<>();
            boolean found = prefix.isEmpty();
            Enumeration<? extends ZipEntry> en = z.entries();
            while (en.hasMoreElements()) {
                ZipEntry e = en.nextElement();
                String name = zipNorm(e.getName());
                if (name.isEmpty()) continue;
                String full = name + (e.isDirectory() ? "/" : "");
                if (!prefix.isEmpty()) {
                    if (!full.startsWith(prefix)) continue;
                    found = true;
                    if (name.length() + 1 <= prefix.length()) continue;   // klasörün kendisi
                }
                String rest = name.substring(prefix.length());
                if (rest.isEmpty()) continue;
                int sl = rest.indexOf('/');
                String seg = sl < 0 ? rest : rest.substring(0, sl);
                if (seg.isEmpty() || seg.startsWith(".")) continue;
                boolean dir = sl >= 0 || e.isDirectory();
                JSONObject o = out.get(seg);
                if (o == null) {
                    o = new JSONObject();
                    o.put("n", seg);
                    o.put("d", dir ? 1 : 0);
                    o.put("s", dir ? 0 : Math.max(0, e.getSize()));
                    o.put("m", e.getTime() > 0 ? e.getTime() : zr.zip.lastModified());
                    out.put(seg, o);
                } else if (dir && o.optInt("d") == 0) {
                    o.put("d", 1);
                    o.put("s", 0);
                }
            }
            if (!found) return err("Zip içinde klasör bulunamadı");
            JSONArray arr = new JSONArray();
            for (JSONObject o : out.values()) arr.put(o);
            JSONObject res = new JSONObject();
            res.put("ok", true);
            res.put("items", arr);
            return res.toString();
        } catch (java.util.zip.ZipException e) {
            return err("Bu zip dosyası açılamadı (bozuk ya da şifreli olabilir)");
        } catch (Throwable t) {
            return err("Zip okunamadı");
        } finally {
            if (z != null) try { z.close(); } catch (IOException ignored) { }
        }
    }

    private static String zipList(ZRef zr) { return zipListJson(zr); }

    /** Zip içindeki tek bir dosyayı önbelleğe çıkarır (aynı zip + aynı girdi tekrar çıkarılmaz). */
    private static File zipToCache(Context ctx, ZRef zr) throws IOException {
        File cacheRoot = new File(ctx.getCacheDir(), "zipview");
        String key = Integer.toHexString((zr.zip.getCanonicalPath() + "|" + zr.zip.lastModified() + "|" + zr.zip.length()).hashCode());
        File keyDir = new File(cacheRoot, key);
        File out = new File(keyDir, zr.inner);
        String kd = keyDir.getCanonicalPath();
        if (!out.getCanonicalPath().startsWith(kd + File.separator)) throw new IOException("yol");
        ZipFile z = openZip(zr.zip);
        try {
            ZipEntry hit = null;
            Enumeration<? extends ZipEntry> en = z.entries();
            while (en.hasMoreElements()) {
                ZipEntry e = en.nextElement();
                if (!e.isDirectory() && zipNorm(e.getName()).equals(zr.inner)) { hit = e; break; }
            }
            if (hit == null) throw new IOException("girdi yok");
            if (out.isFile() && (hit.getSize() < 0 || out.length() == hit.getSize())) return out;
            trimCache(cacheRoot, keyDir);
            File par = out.getParentFile();
            if (!par.isDirectory() && !par.mkdirs()) throw new IOException("klasör");
            File tmp = new File(par, out.getName() + ".part");
            InputStream in = z.getInputStream(hit);
            try {
                OutputStream os = new FileOutputStream(tmp);
                try {
                    byte[] buf = new byte[64 * 1024];
                    int n;
                    while ((n = in.read(buf)) > 0) os.write(buf, 0, n);
                } finally { os.close(); }
            } finally { in.close(); }
            if (out.exists()) out.delete();
            if (!tmp.renameTo(out)) throw new IOException("ad");
            return out;
        } finally {
            try { z.close(); } catch (IOException ignored) { }
        }
    }

    private static long dirSize(File d, long cap) {
        long t = 0;
        File[] cs = d.listFiles();
        if (cs == null) return 0;
        for (File c : cs) {
            t += c.isDirectory() ? dirSize(c, cap) : c.length();
            if (t > cap) return t;
        }
        return t;
    }

    /** Önbellek 400 MB'ı aşarsa şu an kullanılan dışındaki her şeyi siler. */
    private static void trimCache(File cacheRoot, File keep) {
        try {
            if (dirSize(cacheRoot, 400L << 20) <= (400L << 20)) return;
            File[] cs = cacheRoot.listFiles();
            if (cs != null) for (File c : cs) if (!c.equals(keep)) deleteRec(c);
        } catch (Throwable ignored) { }
    }

    /** Zip'ten ayıklar. prefix: "" (hepsi) ya da "klasör/" ; dest: hedef klasör. Dönen: [ayıklanan, atlanan] */
    private static int[] zipExtractTo(ZipFile z, String prefix, File dest) throws IOException {
        if (!dest.isDirectory() && !dest.mkdirs()) throw new IOException("hedef");
        String dc = dest.getCanonicalPath();
        long need = 0;
        Enumeration<? extends ZipEntry> en0 = z.entries();
        while (en0.hasMoreElements()) {
            ZipEntry e = en0.nextElement();
            if (!e.isDirectory() && e.getSize() > 0 && zipNorm(e.getName()).startsWith(prefix.isEmpty() ? "" : prefix)) need += e.getSize();
        }
        if (need > dest.getUsableSpace()) throw new IOException("yer");
        int done = 0, skipped = 0;
        Enumeration<? extends ZipEntry> en = z.entries();
        byte[] buf = new byte[64 * 1024];
        while (en.hasMoreElements()) {
            ZipEntry e = en.nextElement();
            String name = zipNorm(e.getName());
            String full = name + (e.isDirectory() ? "/" : "");
            if (name.isEmpty()) continue;
            if (!prefix.isEmpty() && !full.startsWith(prefix)) continue;
            String rel = name.substring(Math.min(prefix.length(), name.length()));
            if (prefix.isEmpty()) rel = name;
            if (rel.isEmpty()) continue;
            boolean badName = false;
            for (String seg : rel.split("/")) if (seg.equals("..") || seg.indexOf('\u0000') >= 0) badName = true;
            File out = new File(dest, rel);
            if (badName || !out.getCanonicalPath().startsWith(dc + File.separator)) { skipped++; continue; }   // zip slip
            if (e.isDirectory()) {
                out.mkdirs();
                done++;
                continue;
            }
            File par = out.getParentFile();
            if (!par.isDirectory() && !par.mkdirs()) { skipped++; continue; }
            if (out.exists()) out = new File(par, uniqueName(par, out.getName()));
            InputStream in = z.getInputStream(e);
            try {
                OutputStream os = new FileOutputStream(out);
                try {
                    int n;
                    while ((n = in.read(buf)) > 0) os.write(buf, 0, n);
                } finally { os.close(); }
            } finally { in.close(); }
            if (e.getTime() > 0) out.setLastModified(e.getTime());
            done++;
        }
        return new int[]{done, skipped};
    }

    private static String extractErr(Throwable t) {
        String m = t.getMessage();
        if ("yer".equals(m)) return "Depolamada yeterli yer yok";
        if (t instanceof java.util.zip.ZipException) return "Zip dosyası bozuk ya da şifreli (şifreli zip desteklenmiyor)";
        return "Ayıklanamadı";
    }

    private static String doneJson(int n, int skipped, String name) {
        try {
            JSONObject o = new JSONObject();
            o.put("ok", true);
            o.put("n", n);
            o.put("skipped", skipped);
            if (name != null) o.put("dir", name);
            return o.toString();
        } catch (Exception e) {
            return ok();
        }
    }

    /** Zip'in tamamını ayıklar. intoNew: hedef klasörde zip adıyla yeni klasör aç. */
    static String zipExtract(String vzip, String vdest, boolean intoNew) {
        File zip = resolve(vzip);
        File dir = resolve(vdest);
        if (zip == null || !zip.isFile()) return err("Zip dosyası bulunamadı");
        if (dir == null || !dir.isDirectory() || zipSplit(vdest) != null) return err("Hedef klasör geçersiz");
        ZipFile z = null;
        try {
            z = openZip(zip);
            File target = dir;
            String shown = null;
            if (intoNew) {
                String nm = zip.getName();
                int dot = nm.lastIndexOf('.');
                if (dot > 0) nm = nm.substring(0, dot);
                shown = uniqueName(dir, nm);
                target = new File(dir, shown);
            }
            int[] r = zipExtractTo(z, "", target);
            return doneJson(r[0], r[1], shown);
        } catch (Throwable t) {
            return err(extractErr(t));
        } finally {
            if (z != null) try { z.close(); } catch (IOException ignored) { }
        }
    }

    /** Zip içindeki bir dosya/klasörü hedef klasöre kopyalar (Gezgin'de zip içinden Kopyala > Yapıştır). */
    private static String zipCopyEntry(String vsrc, String vdest) {
        ZRef zr = zipSplit(vsrc);
        File dir = resolve(vdest);
        if (zr == null || zr.inner.isEmpty()) return err("Kaynak bulunamadı");
        if (dir == null || !dir.isDirectory()) return err("Hedef klasör geçersiz");
        ZipFile z = null;
        try {
            z = openZip(zr.zip);
            String name = zr.inner.substring(zr.inner.lastIndexOf('/') + 1);
            boolean isDir = false;
            ZipEntry file = null;
            Enumeration<? extends ZipEntry> en = z.entries();
            while (en.hasMoreElements()) {
                ZipEntry e = en.nextElement();
                String n = zipNorm(e.getName());
                if (n.equals(zr.inner) && !e.isDirectory()) { file = e; }
                else if (n.equals(zr.inner) || n.startsWith(zr.inner + "/")) { isDir = true; }
            }
            if (isDir) {
                File target = new File(dir, uniqueName(dir, name));
                int[] r = zipExtractTo(z, zr.inner + "/", target);
                return doneJson(r[0], r[1], null);
            }
            if (file == null) return err("Zip içinde öğe bulunamadı");
            File out = new File(dir, uniqueName(dir, name));
            InputStream in = z.getInputStream(file);
            try {
                OutputStream os = new FileOutputStream(out);
                try {
                    byte[] buf = new byte[64 * 1024];
                    int n;
                    while ((n = in.read(buf)) > 0) os.write(buf, 0, n);
                } finally { os.close(); }
            } finally { in.close(); }
            if (file.getTime() > 0) out.setLastModified(file.getTime());
            return doneJson(1, 0, null);
        } catch (Throwable t) {
            return err(extractErr(t));
        } finally {
            if (z != null) try { z.close(); } catch (IOException ignored) { }
        }
    }

    private static int zipAdd(ZipOutputStream zos, File f, String name, String outCanon, byte[] buf, int[] bad) {
        try {
            if (f.getCanonicalPath().equals(outCanon)) return 0;                       // yazılmakta olan zip'in kendisi
            if (!f.getCanonicalPath().equals(new File(f.getParentFile().getCanonicalFile(), f.getName()).getPath())) return 0;   // sembolik bağ
            if (f.isDirectory()) {
                ZipEntry de = new ZipEntry(name + "/");
                de.setTime(f.lastModified());
                zos.putNextEntry(de);
                zos.closeEntry();
                int c = 0;
                File[] cs = f.listFiles();
                if (cs != null) for (File ch : cs) c += zipAdd(zos, ch, name + "/" + ch.getName(), outCanon, buf, bad);
                return c;
            }
            ZipEntry e = new ZipEntry(name);
            e.setTime(f.lastModified());
            InputStream in = new FileInputStream(f);
            try {
                zos.putNextEntry(e);
                int n;
                while ((n = in.read(buf)) > 0) zos.write(buf, 0, n);
                zos.closeEntry();
            } finally { in.close(); }
            return 1;
        } catch (IOException ex) {
            bad[0]++;
            return 0;
        }
    }

    /** Seçili öğeleri (names: JSON dizisi) vparent içinde zipName adlı zip'e sıkıştırır. */
    static String zipCreate(String vparent, String namesJson, String zipName) {
        if (!validName(zipName)) return err("Geçersiz ad");
        if (zipSplit(vparent) != null) return err(ZIP_RO);
        File dir = resolve(vparent);
        if (dir == null || !dir.isDirectory()) return err("Geçersiz klasör");
        String zn = zipName.trim();
        if (!zn.toLowerCase(Locale.ROOT).endsWith(".zip")) zn += ".zip";
        File out = new File(dir, uniqueName(dir, zn));
        boolean atRoot = vparent == null || vparent.isEmpty();
        try {
            JSONArray names = new JSONArray(namesJson);
            if (names.length() == 0) return err("Sıkıştırılacak öğe yok");
            String outCanon = out.getCanonicalPath();
            int[] bad = new int[1];
            int count = 0;
            byte[] buf = new byte[64 * 1024];
            ZipOutputStream zos = new ZipOutputStream(new java.io.BufferedOutputStream(new FileOutputStream(out), 64 * 1024));
            try {
                zos.setLevel(6);
                for (int i = 0; i < names.length(); i++) {
                    String n = names.getString(i);
                    if (!validName(n)) continue;
                    File f = new File(dir, atRoot ? toReal(n) : n);
                    if (!f.exists()) continue;
                    count += zipAdd(zos, f, n, outCanon, buf, bad);
                }
            } finally {
                zos.close();
            }
            if (count == 0) { out.delete(); return err("Sıkıştırılacak dosya bulunamadı"); }
            JSONObject o = new JSONObject();
            o.put("ok", true);
            o.put("name", out.getName());
            o.put("n", count);
            o.put("skipped", bad[0]);
            return o.toString();
        } catch (Throwable t) {
            try { out.delete(); } catch (Throwable ignored) { }
            return err("Sıkıştırılamadı");
        }
    }


    // ------------------------------------------------------------ Media Player: dosyayı WebView'e akıt (Range destekli)

    private static String mediaMime(File f) {
        String n = f.getName().toLowerCase(Locale.ROOT);
        int d = n.lastIndexOf('.');
        String e = d >= 0 ? n.substring(d + 1) : "";
        switch (e) {
            case "mkv": return "video/x-matroska";
            case "mp4": case "m4v": return "video/mp4";
            case "webm": return "video/webm";
            case "3gp": return "video/3gpp";
            case "avi": return "video/x-msvideo";
            case "mov": return "video/quicktime";
            case "wmv": return "video/x-ms-wmv";
            case "flv": return "video/x-flv";
            case "mp3": return "audio/mpeg";
            case "m4a": return "audio/mp4";
            case "aac": return "audio/aac";
            case "flac": return "audio/flac";
            case "wav": return "audio/wav";
            case "ogg": case "opus": return "audio/ogg";
            case "wma": return "audio/x-ms-wma";
            case "jpg": case "jpeg": return "image/jpeg";
            case "png": return "image/png";
            case "gif": return "image/gif";
            case "webp": return "image/webp";
            case "bmp": return "image/bmp";
            case "svg": return "image/svg+xml";
            case "avif": return "image/avif";
            // web sayfaları (HTML'i tarayıcı penceresinde açmak için)
            case "html": case "htm": case "xhtml": return "text/html";
            case "css": return "text/css";
            case "js": case "mjs": return "application/javascript";
            case "json": case "map": return "application/json";
            case "webmanifest": return "application/manifest+json";
            case "xml": return "text/xml";
            case "txt": return "text/plain";
            case "csv": return "text/csv";
            case "wasm": return "application/wasm";
            case "woff": return "font/woff";
            case "woff2": return "font/woff2";
            case "ttf": return "font/ttf";
            case "otf": return "font/otf";
            case "ico": return "image/x-icon";
            case "pdf": return "application/pdf";
            default: break;
        }
        String m = mimeOf(f);
        return m == null ? "application/octet-stream" : m;
    }

    /** Dosyayı (isteğe bağlı Range ile) WebResourceResponse olarak verir. Yoksa/izin yoksa 404. */
    static android.webkit.WebResourceResponse serve(Context ctx, String vpath, String rangeHeader) {
        return serve(ctx, vpath, rangeHeader, false);
    }

    /** web=true: tarayıcı penceresindeki sayfa için (CORS başlığı yok; metin türleri UTF-8 olarak işaretlenir). */
    private static android.webkit.WebResourceResponse serve(Context ctx, String vpath, String rangeHeader, boolean web) {
        java.util.Map<String, String> h = new java.util.HashMap<>();
        if (!web) h.put("Access-Control-Allow-Origin", "*");
        h.put("Accept-Ranges", "bytes");
        h.put("Cache-Control", "no-store");
        try {
            if (!hasAccess(ctx)) throw new IOException("noaccess");
            File f = fileFor(ctx, vpath);
            if (f == null || !f.isFile()) throw new IOException("nofile");
            final long len = f.length();
            String mime = mediaMime(f);
            final String enc = (mime.startsWith("text/") || mime.equals("application/javascript") || mime.equals("application/json")
                    || mime.endsWith("+xml") || mime.endsWith("+json")) ? "utf-8" : null;
            long start = 0, end = len - 1;
            boolean partial = false;
            if (rangeHeader != null && rangeHeader.startsWith("bytes=") && len > 0) {
                String r = rangeHeader.substring(6).split(",")[0].trim();
                int dash = r.indexOf('-');
                if (dash >= 0) {
                    String a = r.substring(0, dash).trim(), b = r.substring(dash + 1).trim();
                    try {
                        if (a.isEmpty()) {                       // "-N": son N bayt
                            long n = Long.parseLong(b);
                            start = Math.max(0, len - n);
                        } else {
                            start = Long.parseLong(a);
                            if (!b.isEmpty()) end = Math.min(len - 1, Long.parseLong(b));
                        }
                        partial = true;
                    } catch (NumberFormatException ignored) { partial = false; start = 0; end = len - 1; }
                }
                if (partial && (start > end || start >= len)) {
                    h.put("Content-Range", "bytes */" + len);
                    return new android.webkit.WebResourceResponse(mime, null, 416, "Range Not Satisfiable", h,
                            new java.io.ByteArrayInputStream(new byte[0]));
                }
            }
            final long count = len == 0 ? 0 : end - start + 1;
            final java.io.RandomAccessFile raf = new java.io.RandomAccessFile(f, "r");
            raf.seek(start);
            InputStream in = new InputStream() {
                long left = count;
                @Override public int read() throws IOException {
                    if (left <= 0) return -1;
                    int b = raf.read();
                    if (b >= 0) left--;
                    return b;
                }
                @Override public int read(byte[] buf, int off, int n) throws IOException {
                    if (left <= 0) return -1;
                    int got = raf.read(buf, off, (int) Math.min(n, left));
                    if (got > 0) left -= got;
                    return got;
                }
                @Override public int available() { return (int) Math.min(left, 1 << 20); }
                @Override public void close() throws IOException { raf.close(); }
            };
            h.put("Content-Length", String.valueOf(count));
            if (partial) {
                h.put("Content-Range", "bytes " + start + "-" + end + "/" + len);
                return new android.webkit.WebResourceResponse(mime, enc, 206, "Partial Content", h, in);
            }
            return new android.webkit.WebResourceResponse(mime, enc, 200, "OK", h, in);
        } catch (Throwable t) {
            return new android.webkit.WebResourceResponse("text/plain", "utf-8", 404, "Not Found", h,
                    new java.io.ByteArrayInputStream(new byte[0]));
        }
    }

    // ------------------------------------------------------------ HTML dosyalarını tarayıcı pencerelerinde aç

    /** Telefon dosyalarını tarayıcı pencerelerine (yerel WebView) sunan sahte adres: https://w7media.local/h/<anahtar>/<dosya> */
    static final String WEB_HOST = "w7media.local";
    private static final String WEB_PREFS = "w7web";
    private static final Object WEB_LOCK = new Object();

    /**
     * HTML dosyasının tarayıcıda açılacağı adresi verir: {"ok":true,"url":"https://w7media.local/h/<anahtar>/<ad>"}.
     * Anahtar (rastgele) dosyanın BULUNDUĞU klasöre bağlıdır: sayfa yalnızca o klasörün içini (css, js, resim, alt klasörler)
     * okuyabilir, dışına çıkamaz. Anahtarı bilmeyen web siteleri telefon dosyalarına erişemez.
     */
    static String webUrl(Context ctx, String vpath) {
        if (!hasAccess(ctx)) return err("Dosyalara erişim izni gerekli");
        if (vpath == null || vpath.isEmpty()) return err("Dosya bulunamadı");
        if (zipSplit(vpath) != null) return err("Zip içindeki sayfa önce ayıklanmalı (sağ tık → Buraya ayıkla)");
        File f = resolve(vpath);
        if (f == null || !f.isFile()) return err("Dosya bulunamadı");
        int cut = vpath.lastIndexOf('/');
        String base = cut < 0 ? "" : vpath.substring(0, cut);
        String name = cut < 0 ? vpath : vpath.substring(cut + 1);
        try {
            JSONObject o = new JSONObject();
            o.put("ok", true);
            o.put("url", "https://" + WEB_HOST + "/h/" + webToken(ctx, base) + "/" + Uri.encode(name));
            return o.toString();
        } catch (Throwable t) {
            return err("Açılamadı");
        }
    }

    /** Klasör için kalıcı rastgele anahtar (uygulama yeniden açılınca Nova'nın kayıtlı sekmeleri çalışsın diye saklanır). */
    private static String webToken(Context ctx, String base) {
        android.content.SharedPreferences sp = ctx.getSharedPreferences(WEB_PREFS, Context.MODE_PRIVATE);
        synchronized (WEB_LOCK) {
            Map<String, ?> all = sp.getAll();
            for (Map.Entry<String, ?> e : all.entrySet()) {
                if (base.equals(e.getValue())) return e.getKey();
            }
            byte[] b = new byte[12];
            new java.security.SecureRandom().nextBytes(b);
            StringBuilder sb = new StringBuilder();
            for (byte x : b) sb.append(String.format(Locale.ROOT, "%02x", x));
            String tok = sb.toString();
            android.content.SharedPreferences.Editor ed = sp.edit();
            if (all.size() >= 200) ed.clear();   // sınır: en eski anahtarlar silinir
            ed.putString(tok, base);
            ed.apply();
            return tok;
        }
    }

    private static android.webkit.WebResourceResponse webNotFound() {
        return new android.webkit.WebResourceResponse("text/plain", "utf-8", 404, "Not Found",
                new java.util.HashMap<String, String>(), new java.io.ByteArrayInputStream(new byte[0]));
    }

    /** /h/<anahtar>/<yol> isteğini karşılar. Geçersiz anahtar, kök/klasör dışına çıkma ya da dosya yoksa 404. */
    static android.webkit.WebResourceResponse serveWeb(Context ctx, String encPath, String rangeHeader) {
        try {
            if (encPath == null || !encPath.startsWith("/h/") || !hasAccess(ctx)) return webNotFound();
            String rest = encPath.substring(3);
            int sl = rest.indexOf('/');
            if (sl <= 0) return webNotFound();
            String base = ctx.getSharedPreferences(WEB_PREFS, Context.MODE_PRIVATE).getString(rest.substring(0, sl), null);
            if (base == null) return webNotFound();
            List<String> parts = new ArrayList<>();
            if (!base.isEmpty()) for (String q : base.split("/")) parts.add(q);
            String rel = rest.substring(sl + 1);
            if (!rel.isEmpty()) {
                String[] segs = rel.split("/", -1);
                for (int i = 0; i < segs.length; i++) {
                    String q = Uri.decode(segs[i]);
                    if (q.isEmpty() && i == segs.length - 1) break;   // sondaki "/"
                    if (q.isEmpty() || q.equals(".") || q.equals("..") || q.indexOf('/') >= 0
                            || q.indexOf('\\') >= 0 || q.indexOf('\u0000') >= 0) return webNotFound();
                    parts.add(q);
                }
            }
            StringBuilder vp = new StringBuilder();
            for (String q : parts) { if (vp.length() > 0) vp.append('/'); vp.append(q); }
            String vpath = vp.toString();
            File f = resolve(vpath);
            if (f != null && f.isDirectory()) vpath = vpath.isEmpty() ? "index.html" : vpath + "/index.html";
            return serve(ctx, vpath, rangeHeader, true);
        } catch (Throwable t) {
            return webNotFound();
        }
    }

    static boolean hasAccess(Context ctx) {
        if (Build.VERSION.SDK_INT >= 30) return Environment.isExternalStorageManager();
        if (Build.VERSION.SDK_INT >= 23) {
            return ctx.checkSelfPermission(android.Manifest.permission.READ_EXTERNAL_STORAGE) == android.content.pm.PackageManager.PERMISSION_GRANTED
                    && ctx.checkSelfPermission(android.Manifest.permission.WRITE_EXTERNAL_STORAGE) == android.content.pm.PackageManager.PERMISSION_GRANTED;
        }
        return true;
    }
}
