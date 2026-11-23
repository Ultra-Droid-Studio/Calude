package com.nexus.vr;

import android.app.Activity;
import android.os.Bundle;
import android.view.WindowManager;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.WebResourceRequest;
import android.net.Uri;
import android.os.Build;
import android.webkit.CookieManager;
import android.webkit.ConsoleMessage;
import android.webkit.WebResourceError;
import android.util.Log;

/** Separate offline Windows 7 simulator screen. The NEXUS VR WebView remains untouched. */
public class Win7Activity extends Activity {
    private WebView view;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        view = new WebView(this);
        view.setBackgroundColor(0xff000000);
        WebSettings s = view.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setDatabaseEnabled(true);
        // The bundled simulator is a local asset. Remote sites opened by its
        // built-in Browser/Web Apps are rendered by this Android System WebView.
        s.setAllowFileAccess(true);
        s.setAllowContentAccess(false);
        s.setAllowFileAccessFromFileURLs(false);
        s.setAllowUniversalAccessFromFileURLs(false);
        s.setGeolocationEnabled(false);
        s.setSaveFormData(false);
        if (Build.VERSION.SDK_INT >= 26) s.setSafeBrowsingEnabled(true);
        s.setJavaScriptCanOpenWindowsAutomatically(true);
        s.setSupportMultipleWindows(false);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setUseWideViewPort(true);
        // The simulator declares its own responsive viewport; overview mode scales the
        // entire desktop to fit and can make controls/layout behave inconsistently.
        s.setLoadWithOverviewMode(false);
        s.setTextZoom(100);
        s.setMixedContentMode(WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE);
        // Present as a normal mobile Chrome tab for remote sites opened by the simulator's
        // Browser/Web Apps, not a bare embedded WebView: strip the "; wv" marker and stray
        // "Version/x.y" token that make sites show an "update your browser" banner.
        s.setUserAgentString(s.getUserAgentString().replace("; wv", "").replaceAll("Version/\\d+\\.\\d+ ", ""));
        WebView.setWebContentsDebuggingEnabled((getApplicationInfo().flags & android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0);
        CookieManager cookies = CookieManager.getInstance();
        cookies.setAcceptCookie(true);
        cookies.setAcceptThirdPartyCookies(view, true);
        view.setWebViewClient(new WebViewClient() {
            @Override public boolean shouldOverrideUrlLoading(WebView v, WebResourceRequest request) {
                Uri uri = request.getUrl();
                String scheme = uri.getScheme() == null ? "" : uri.getScheme().toLowerCase();
                // Keep web links in the Android WebView engine. Reject app-launch
                // schemes such as intent:// and market:// from embedded pages.
                return !("http".equals(scheme) || "https".equals(scheme)
                        || "about".equals(scheme) || "blob".equals(scheme)
                        || "data".equals(scheme) || "file".equals(scheme));
            }
            @Override public void onReceivedError(WebView v, WebResourceRequest request, WebResourceError error) {
                super.onReceivedError(v, request, error);
                if (request.isForMainFrame()) {
                    Log.e("NEXUS-Win7", "Simülatör yükleme hatası: " + request.getUrl()
                            + " code=" + error.getErrorCode() + " " + error.getDescription());
                    String html = "<!doctype html><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>"
                            + "<body style='font:16px sans-serif;background:#101820;color:white;padding:24px'>"
                            + "<h2>Windows 7 açılamadı</h2><p>Yerel simülatör kaynağı yüklenemedi. Logcat'teki NEXUS-Win7 kaydını kontrol edin.</p>"
                            + "<button onclick='location.reload()'>Tekrar dene</button></body>";
                    v.loadDataWithBaseURL("file:///android_asset/", html, "text/html", "UTF-8", null);
                }
            }
        });
        view.setWebChromeClient(new WebChromeClient() {
            @Override public boolean onConsoleMessage(ConsoleMessage message) {
                if (message.messageLevel() == ConsoleMessage.MessageLevel.ERROR) {
                    Log.e("NEXUS-Win7-JS", message.message() + " (" + message.sourceId() + ":" + message.lineNumber() + ")");
                }
                return true;
            }
        });
        setContentView(view);
        view.loadUrl("file:///android_asset/win7simu.html");
    }

    @Override public void onBackPressed() {
        if (view != null && view.canGoBack()) view.goBack();
        else super.onBackPressed();
    }

    @Override protected void onDestroy() {
        if (view != null) { view.stopLoading(); view.destroy(); view = null; }
        super.onDestroy();
    }
}
