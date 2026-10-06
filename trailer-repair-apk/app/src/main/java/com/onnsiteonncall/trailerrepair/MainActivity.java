package com.onnsiteonncall.trailerrepair;
import android.Manifest; import android.app.*; import android.os.*; import android.print.*; import android.webkit.*; import android.content.*; import android.content.pm.PackageManager; import android.net.Uri;
public class MainActivity extends Activity {
 WebView web; ValueCallback<Uri[]> upload; static final int FILE_REQ=41;
 @Override public void onCreate(Bundle b){super.onCreate(b);web=new WebView(this);setContentView(web);WebSettings s=web.getSettings();s.setJavaScriptEnabled(true);s.setDomStorageEnabled(true);s.setAllowFileAccess(true);s.setAllowContentAccess(true);
 web.setWebChromeClient(new WebChromeClient(){@Override public boolean onShowFileChooser(WebView v,ValueCallback<Uri[]> cb,FileChooserParams p){upload=cb;try{startActivityForResult(p.createIntent(),FILE_REQ);}catch(Exception e){upload=null;return false;}return true;}@Override public void onPermissionRequest(final PermissionRequest r){runOnUiThread(()->r.grant(r.getResources()));}});
 web.addJavascriptInterface(new Object(){@JavascriptInterface public void printPage(){runOnUiThread(()->doPrint());}},"Android");
 web.setWebViewClient(new WebViewClient(){@Override public void onPageFinished(WebView v,String u){v.evaluateJavascript("window.print=function(){if(window.Android){Android.printPage();}};",null);}});
 if(Build.VERSION.SDK_INT>=23&&checkSelfPermission(Manifest.permission.CAMERA)!=PackageManager.PERMISSION_GRANTED)requestPermissions(new String[]{Manifest.permission.CAMERA},7);
 web.loadUrl("https://jarvis-native-watch-bridge.floot.app");}
 void doPrint(){PrintManager pm=(PrintManager)getSystemService(PRINT_SERVICE);pm.print("Trailer Repair Forms",web.createPrintDocumentAdapter("Trailer Repair Forms"),new PrintAttributes.Builder().build());}
 @Override protected void onActivityResult(int r,int c,Intent d){super.onActivityResult(r,c,d);if(r==FILE_REQ&&upload!=null){Uri[] x=null;if(c==RESULT_OK&&d!=null){if(d.getClipData()!=null){int n=d.getClipData().getItemCount();x=new Uri[n];for(int i=0;i<n;i++)x[i]=d.getClipData().getItemAt(i).getUri();}else if(d.getData()!=null)x=new Uri[]{d.getData()};}upload.onReceiveValue(x);upload=null;}}
 @Override public void onBackPressed(){if(web.canGoBack())web.goBack();else super.onBackPressed();}
}