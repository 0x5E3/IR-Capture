# Signing and notarizing IR Capture (for Lowell)

Once this is done, every download opens on the first double-click, with no "Open Anyway" step. Until then, builds still work; they're just unsigned.

You do steps 1–4 once. They take about an hour, most of it waiting for Apple. Nothing here needs Terminal except one copy-and-paste in step 3.

## 1. Join the Apple Developer Program ($99 a year)

1. Go to **developer.apple.com/programs** and click **Enroll**.
2. Sign in with your Apple ID.
3. Choose **Organization** to sell as Swell Amplification LLC (the app then shows the company name). Apple asks for the company's D-U-N-S number; if you don't have one, Apple's page links to a free lookup. Choosing **Individual** is quicker and shows your own name instead.
4. Pay. Apple's approval usually takes a day or two for an organization.

## 2. Make the "Developer ID Application" certificate

The easiest way is with Xcode (free in the App Store):

1. Install **Xcode** and open it once.
2. **Xcode › Settings › Accounts**. Click **+**, choose **Apple ID**, and sign in.
3. Select your team, click **Manage Certificates…**, click **+**, and choose **Developer ID Application**.
4. Close Xcode. The certificate is now in your Mac's keychain.

## 3. Export the certificate for GitHub

1. Open **Keychain Access** (in Applications › Utilities).
2. In **My Certificates**, find **Developer ID Application: …** Right-click it and choose **Export…**.
3. Save it as `cert.p12` on your Desktop. It asks for a password to protect the file: make one up and keep it (you'll paste it into GitHub in step 4).
4. Open **Terminal** and paste this line, then press Return. It copies the file, in the text form GitHub needs, to your clipboard:

   ```
   base64 -i ~/Desktop/cert.p12 | pbcopy
   ```

Keep the clipboard for step 4. Delete `cert.p12` from the Desktop when you're done.

## 4. Make the notarization key, and put everything in GitHub

**The key:**
1. Go to **appstoreconnect.apple.com** › **Users and Access** › **Integrations** › **App Store Connect API** › **Team Keys**.
2. Click **+**. Name it "IR Capture CI", give it **Developer** access, click **Generate**.
3. Note the **Key ID** and, above the list, the **Issuer ID**.
4. Click **Download** next to the key. You get a file like `AuthKey_ABC123.p8`. Apple only lets you download it once.

**GitHub:** go to **github.com/0x5E3/IR-Capture › Settings › Secrets and variables › Actions**, and click **New repository secret** for each of these:

| Name | What to paste |
|---|---|
| `MACOS_CERT_P12` | The clipboard from step 3 (a long block of letters) |
| `MACOS_CERT_PASSWORD` | The password you made in step 3 |
| `NOTARY_KEY_P8` | Open the `.p8` file in TextEdit and paste everything in it, including the BEGIN and END lines |
| `NOTARY_KEY_ID` | The Key ID |
| `NOTARY_ISSUER_ID` | The Issuer ID |

That's all. The next build signs and notarizes itself. The release notes on the `latest` release say "Signed with Developer ID" when it worked.

## 5. Publishing a real release

1. On GitHub, go to **Releases › Draft a new release**.
2. Under **Choose a tag**, type `v1.0.0` (it must match the `VERSION` file) and choose **Create new tag on publish**.
3. Click **Publish release**.

The build then makes a signed, notarized `IR-Capture.dmg` and attaches it to that release. That's the file to put on swellamps.com.

## If something goes wrong

The build log on GitHub (**Actions** tab) says which step failed and why. The usual causes: a password typo in `MACOS_CERT_PASSWORD`, the `.p8` pasted without its BEGIN/END lines, or a tag that doesn't match `VERSION`. Start a new chat and paste the error.
