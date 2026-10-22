# Signing and notarizing IR Capture (for Lowell)

After this setup, each download opens on the first double-click, without the "Open Anyway" step. Until then, builds are unsigned but functional.

Steps 1–4 are done once. Total time is about one hour, mostly waiting for Apple. Terminal is required only for one copy-and-paste in step 3.

## 1. Join the Apple Developer Program ($99 a year)

1. Go to **developer.apple.com/programs** and click **Enroll**.
2. Sign in with the Apple ID.
3. Choose **Organization** to sell as Swell Amplification LLC. The company name is then shown for the app. A D-U-N-S number for the company is required. If no number is available, use the free lookup linked on the Apple page. **Individual** enrollment is faster and shows a personal name instead.
4. Pay the fee. Approval for an organization usually takes one to two days.

## 2. Make the "Developer ID Application" certificate

Use Xcode (free in the App Store):

1. Install **Xcode** and open it once.
2. **Xcode › Settings › Accounts**. Click **+**, choose **Apple ID**, and sign in.
3. Select the team, click **Manage Certificates…**, click **+**, and choose **Developer ID Application**.
4. Close Xcode. The certificate is now in the Mac keychain.

## 3. Export the certificate for GitHub

1. Open **Keychain Access** (in Applications › Utilities).
2. In **My Certificates**, find **Developer ID Application: …** Right-click it and choose **Export…**.
3. Save it as `cert.p12` on the Desktop. Enter a new password to protect the file. Record the password; it is required in step 4.
4. Open **Terminal**, paste this line, and press Return. The command copies the file to the clipboard in the text format required by GitHub:

   ```
   base64 -i ~/Desktop/cert.p12 | pbcopy
   ```

Do not copy anything else before step 4. Delete `cert.p12` from the Desktop after step 4.

## 4. Make the notarization key and add the secrets to GitHub

**The key:**
1. Go to **appstoreconnect.apple.com** › **Users and Access** › **Integrations** › **App Store Connect API** › **Team Keys**.
2. Click **+**. Name it "IR Capture CI", give it **Developer** access, click **Generate**.
3. Note the **Key ID** and, above the list, the **Issuer ID**.
4. Click **Download** next to the key. The file name is similar to `AuthKey_ABC123.p8`. The key can be downloaded only once.

**GitHub:** go to **github.com/0x5E3/IR-Capture › Settings › Secrets and variables › Actions**, and click **New repository secret** for each of these:

| Name | What to paste |
|---|---|
| `MACOS_CERT_P12` | The clipboard from step 3 (a long block of letters) |
| `MACOS_CERT_PASSWORD` | The password from step 3 |
| `NOTARY_KEY_P8` | Open the `.p8` file in TextEdit and paste the full contents, including the BEGIN and END lines |
| `NOTARY_KEY_ID` | The Key ID |
| `NOTARY_ISSUER_ID` | The Issuer ID |

Setup is complete. The next build is signed and notarized. If signing succeeded, the release notes of the `latest` release contain "Signed with Developer ID".

## 5. Publishing a real release

1. On GitHub, go to **Releases › Draft a new release**.
2. Under **Choose a tag**, type `v1.0.0` (it must match the `VERSION` file) and choose **Create new tag on publish**.
3. Click **Publish release**.

A signed, notarized `IR-Capture.dmg` is then built and attached to that release. Use this file on swellamps.com.

## Troubleshooting

The build log on GitHub (**Actions** tab) lists the failed step and the error. Common causes: a password typo in `MACOS_CERT_PASSWORD`, the `.p8` contents pasted without the BEGIN/END lines, or a tag that does not match `VERSION`. Start a new chat and paste the error.
