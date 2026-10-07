package ai.apteva.mobile.data

import kotlinx.serialization.SerializationException
import kotlinx.serialization.decodeFromString
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Test

class ApiClientContractTest {
    @Test
    fun contractVersionMatchesNativeV1Release() {
        assertEquals("1.2.0", AptevaClientContract.VERSION)
    }

    @Test
    fun serverUrlNormalizationEnforcesSharedSecurityBoundary() {
        assertEquals("https://example.apteva.test", ApiClient.normalizeServer("example.apteva.test"))
        assertThrows(ApiException::class.java) { ApiClient.normalizeServer("http://example.apteva.test") }
        assertThrows(ApiException::class.java) { ApiClient.normalizeServer("https://user:secret@example.apteva.test") }
        assertThrows(ApiException::class.java) { ApiClient.normalizeServer("https://example.apteva.test?token=secret") }
        assertThrows(ApiException::class.java) { ApiClient.normalizeServer("https://example.apteva.test/#fragment") }
    }

    @Test
    fun installedAppLifecycleFieldsCannotBeInventedByTheClient() {
        val incomplete = """{"name":"calendar","display_name":"Calendar"}"""
        assertThrows(SerializationException::class.java) {
            ApiClient.json.decodeFromString<InstalledApp>(incomplete)
        }
    }

    @Test
    fun installedAppDefaultsDeprecatedForOlderServers() {
        val response = """{
            "install_id":1,
            "app_id":2,
            "name":"calendar",
            "display_name":"Calendar",
            "version":"1.0.0",
            "project_id":"demo",
            "status":"active",
            "source":"registry",
            "upgrade_policy":"manual"
        }"""

        val app = ApiClient.json.decodeFromString<InstalledApp>(response)

        assertFalse(app.deprecated)
    }

    @Test
    fun marketplaceAppDefaultsDeprecatedForOlderRegistries() {
        val response = """{
            "name":"calendar",
            "version":"1.0.0",
            "official":true,
            "installed":false,
            "builtin":false
        }"""

        val app = ApiClient.json.decodeFromString<MarketplaceApp>(response)

        assertFalse(app.deprecated)
    }
}
