package __PACKAGE__

import android.app.Activity
import android.content.Intent
import com.google.android.gms.auth.api.signin.GoogleSignIn
import com.google.android.gms.auth.api.signin.GoogleSignInOptions
import com.google.android.gms.common.api.ApiException
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Independent native Google SDK sign-in for diagnosing and recovering from
// Flutter Google Sign-In failures. Never print tokens, emails or passwords.
internal class JarvisNativeGoogleAuthBridge(private val activity: Activity) {
    private val requestCode = 0x5183
    private var pending: MethodChannel.Result? = null
    private var pendingMode: String? = null

    fun register(engine: FlutterEngine) {
        MethodChannel(
            engine.dartExecutor.binaryMessenger, "jarvis.native_google_auth"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "signInWithWebClient" -> {
                    val webId = call.argument<String>("webClientId").orEmpty().trim()
                    if (!Regex("^[0-9]+-[A-Za-z0-9_-]+\\.apps\\.googleusercontent\\.com$").matches(webId)) {
                        result.error("INVALID_CLIENT_ID", "Invalid Google Web client format", null)
                    } else {
                        openPicker(result, webId)
                    }
                }
                "testAndroidOnly" -> openPicker(result, null)
                else -> result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun openPicker(result: MethodChannel.Result, webId: String?) {
        if (pending != null) {
            result.error("GOOGLE_BUSY", "Google account selection already in progress", null)
            return
        }
        try {
            val options = GoogleSignInOptions.Builder(GoogleSignInOptions.DEFAULT_SIGN_IN)
                .requestEmail().apply {
                    if (webId != null) requestIdToken(webId)
                }.build()
            pending = result
            pendingMode = if (webId == null) "android" else "web"
            activity.startActivityForResult(
                GoogleSignIn.getClient(activity, options).signInIntent, requestCode
            )
        } catch (_: Exception) {
            pending = null
            pendingMode = null
            result.success(mapOf("status" to "native_unavailable"))
        }
    }

    fun onActivityResult(returnedCode: Int, data: Intent?): Boolean {
        if (returnedCode != requestCode) return false
        val callback = pending
        val mode = pendingMode
        pending = null
        pendingMode = null
        try {
            val account = GoogleSignIn.getSignedInAccountFromIntent(data)
                .getResult(ApiException::class.java)
            if (mode == "web") {
                val token = account.idToken.orEmpty()
                if (token.isEmpty()) {
                    callback?.success(mapOf("status" to "no_id_token"))
                } else {
                    // The one-use ID token is exchanged for a server-side
                    // JARVIS session over HTTPS. It is not displayed or logged.
                    callback?.success(mapOf("status" to "ok", "idToken" to token))
                }
            } else {
                callback?.success(mapOf("status" to "android_only_ok"))
            }
        } catch (error: ApiException) {
            callback?.success(
                mapOf("status" to "google_error", "googleStatus" to error.statusCode)
            )
        } catch (_: Exception) {
            callback?.success(mapOf("status" to "native_unavailable"))
        }
        return true
    }
}
