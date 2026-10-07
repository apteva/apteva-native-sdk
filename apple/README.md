# Apple client source

These sources are compiled by the iPhone, iPad, and Mac targets from one
location. Keep them free of target-specific bundle identifiers and navigation
state. Platform UI belongs in the consuming app.

The root Swift package exposes `AptevaNativeSDK` and `AptevaNativeUIKit` as
independent products. App-facing declarations are public; the UIKit product is
only used by iOS/iPadOS. Consume a tested, exact Git release rather than copying
these sources into application targets.
