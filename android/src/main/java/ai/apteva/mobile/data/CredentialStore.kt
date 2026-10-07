package ai.apteva.mobile.data

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import kotlinx.serialization.Serializable
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

@Serializable
data class StoredCredential(
    val serverUrl: String,
    val email: String,
    val apiKey: String,
    val keyId: Long,
)

/** Stores the server-issued private API key behind an Android Keystore key. */
class CredentialStore(context: Context) {
    private val preferences = context.getSharedPreferences("apteva.secure-credentials", Context.MODE_PRIVATE)

    fun load(): StoredCredential? {
        val encrypted = preferences.getString("credential", null) ?: return null
        val iv = preferences.getString("iv", null) ?: return null
        return runCatching {
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(
                Cipher.DECRYPT_MODE,
                secretKey(),
                GCMParameterSpec(128, Base64.decode(iv, Base64.NO_WRAP)),
            )
            val decoded = cipher.doFinal(Base64.decode(encrypted, Base64.NO_WRAP)).decodeToString()
            ApiClient.json.decodeFromString<StoredCredential>(decoded)
        }.getOrNull()
    }

    fun save(credential: StoredCredential) {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        val plaintext = ApiClient.json.encodeToString(StoredCredential.serializer(), credential).encodeToByteArray()
        val encrypted = cipher.doFinal(plaintext)
        preferences.edit()
            .putString("credential", Base64.encodeToString(encrypted, Base64.NO_WRAP))
            .putString("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
            .commit()
    }

    fun clear() {
        preferences.edit().clear().commit()
    }

    private fun secretKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
            init(
                KeyGenParameterSpec.Builder(
                    KEY_ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                )
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setRandomizedEncryptionRequired(true)
                    .build(),
            )
            generateKey()
        }
    }

    private companion object {
        const val KEY_ALIAS = "ai.apteva.mobile.instance-credential"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
    }
}
