# Android client library

This Android library owns Apteva transport, models, secure credentials, and
realtime coordination. The app declares `ai.apteva:native-sdk:1.2.0` and
substitutes this module from the sibling SDK checkout during local development.
The standalone Gradle build can produce a release AAR and Maven publication;
an external repository destination is not configured yet.

Keep Android UI, lifecycle ViewModels, Firebase presentation, and application
resources in the consuming app.
