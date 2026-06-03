---
layout: default
title: Privacy Policy — Server Health
permalink: /privacy/
---

# Privacy Policy

_Last updated: 2026-05-31_

Server Health ("the App") is a Linux server monitor for iOS, distributed by Taha Ercan ("we", "us"). This page describes what information the App handles and what it does not.

The short version: **the App does not collect any personal information from you, and does not transmit data to any party other than the servers you choose to monitor.**

## 1. Data we collect from you

**None.**

The App has no backend, no analytics framework, no crash reporter, and no advertising network. We do not collect:

- Your name, email, or phone number.
- Your IP address (we never see it because the App does not connect to any of our servers).
- Your device identifier.
- Usage statistics, screen views, or feature usage.
- Crash reports (Apple's own crash reporting may be available to you in iOS Settings; that data is not sent to us).

## 2. Data the App stores on your device

All of the following is stored exclusively on your iOS device. It is never uploaded.

- **Server configuration**: the host, port, username, and a display name for each server you add.
- **SSH private key**: generated on your device and stored in the iOS Keychain. Accessibility is set so background checks can run on a locked device, but the key never leaves your device. The matching public key is installed on the server you added.
- **Monitoring rules**: the check type, threshold, interval, and notification template you configure.
- **Metric snapshots**: numerical readings from each check, used to render the 24-hour history chart.
- **Activity log**: the SSH commands run by the App, their outputs, and any errors. Entries older than 3 days are automatically deleted.
- **Background diagnostics counters**: how many automatic checks iOS has fired since install (used to show the user whether background scheduling is working).

You can remove all of this by deleting the App from your device.

## 3. Data sent over the network

The App opens an SSH connection from your iPhone directly to a server **you have added yourself**. Each such connection:

- Authenticates with the SSH key stored in your device's Keychain (after the one-time password setup).
- Sends a single shell command that reads the metric you configured (e.g. `free -b`, `df`, `vnstat`).
- Receives the command's output.
- Closes.

The App does not connect to any server other than the ones you add. The App does not have a backend operated by us.

The server's host key fingerprint is captured on first connection (Trust-On-First-Use) and verified on every subsequent connection. A mismatch blocks the connection and surfaces an error in the App.

## 4. Use of your password during initial setup

When you add a server, the App needs your password **once** to install the SSH key on `~/.ssh/authorized_keys`. The password:

- Lives only in memory during the setup screen.
- Is cleared from memory immediately after the setup succeeds or fails.
- Is never stored on disk, never written to a log, and never sent to any party other than your server.

## 5. In-app purchases

The Pro subscription is processed by Apple via the App Store. We do not receive your payment details. Apple may share aggregate, anonymized purchase metrics with us as part of standard App Store Connect reporting.

To manage or cancel your subscription, use iOS Settings → Apple ID → Subscriptions.

## 6. Children

The App is rated 4+ and does not target children. It does not request, collect, or store information about children specifically.

## 7. Open source

The App's source code is published at [github.com/tahaercan/serverhealth](https://github.com/tahaercan/serverhealth). You can verify the privacy claims above by reading the code.

## 8. Changes to this policy

If we materially change how the App handles data, we will update this page and bump the "Last updated" date. Material changes that affect existing users will also be surfaced inside the App on the next launch.

## 9. Contact

Questions or concerns: open an issue at [github.com/tahaercan/serverhealth/issues](https://github.com/tahaercan/serverhealth/issues).
