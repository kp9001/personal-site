---
title: "Secure SSH with FIDO2"
showToc: true
TocOpen: false
draft: false
hidemeta: false
comments: false
disableShare: true
disableHLJS: false
hideSummary: false
searchHidden: true
ShowReadingTime: false
ShowBreadCrumbs: false
ShowWordCount: false
UseHugoToc: true
---

- [Rerefence from Yubico](https://developers.yubico.com/SSH/Securing_SSH_with_FIDO2.html)

Since version 8.2p1, OpenSSH has supported FIDO2. This allows us to use hardware security keys (such as the [yubikey](https://www.yubico.com/products)) as a second factor for SSH logins, offering a very strong layer of security on top of the existing cryptographic strength of SSH keys. 

### The Problem

SSH keys are ubiquitous, for good reason. Permitting password authentication on an SSH server is widely considered insecure. SSH keys use public key cryptography so that secrets never need to be shared with the server, and modern cryptographic primitives like ed25519 are very strong. 

However, as with any cryptography implementation, they are only as secure as where and how their secrets are stored. If SSH private keys are stored insecurely, they can be exfiltrated, and this is a concern when they often act as single factors. They can be password protected, but this is inconvenient and can be brute forced. 

Unfortunately, even if best security practices are followed, the lack of adequate application sandboxing on most Windows and Linux desktops creates a risk of exfiltration from malware. Similarly, if disk encryption is not used, or if the encryption or boot security of the device is weak, it could be possible to steal private keys with a physical attack. 

### The Solution

Hardware security keys address the above concerns. When you generate an "sk" key pair (i.e. an SSH key pair with a FIDO2 hardware security key), the file that sits on disk and serves as your private key acts as a "handle" for the private key inside the hardware key. On its own, it's insufficient to gain access to your servers. 

By storing the true secrets inside a tamper resistant hardware, which never shares said secrets with any external devices, they are protected from both physical and remote exfiltration. Furthermore, the hardware key will require "presence" to respond to authentication requests, i.e. when the user is required to tap the key. This requires the attacker have physical access to the key itself as it is used, which acts as a strong second factor.

One also has the option to protect their hardware keys with a PIN or [biometrics](https://www.yubico.com/products/yubikey-bio-series/) to strengthen this inherent second factor significantly.  

### Resident Keys

Using hardware security keys in this way offers a great workflow benefit in addition to improved security. Namely, one can create "resident" keys, or "discoverable credentials". This option stores the aforementioned key handle inside the hardware key as well, so that it can be extracted to new device. This is very convenient for anyone who accesses their servers using multiple devices. You only need to set up one pair of keys (per hardware key) and they can be securely accessed from any device.

If you choose to do this, you should make sure you at least configure a PIN for your hardware key, or else anyone who steals it would be able to access your servers! If the hardware key is protected by a PIN, it will require the PIN to release the handle. 

### The Weakest Link

As you take new measures to strengthen your security posture, you should always remember the weakest link. FIDO2 SSH keys are cool, but they won't offer very good protection if your servers still accept the old RSA keys in your `.ssh` directory. You should audit your `authorized_keys` on the server side and ensure that you are always permitting only the weakest keys necessary. If possible, `ed25519-sk` should be preferred everywhere. 

Likewise, you can harden your `sshd_config` by removing unneeded cryptographic primitives and public key types. Here is an example which will only accept `ed25519-sk` and `ecdsa` keys. 

```
KexAlgorithms curve25519-sha256,ecdh-sha2-nistp256
PubkeyAcceptedKeyTypes sk-ssh-ed25519@openssh.com,ecdsa-sha2-nistp256
```

### Commands

The following commands should work on any modern Linux distro running OpenSSH version 8.2p1 or higher. On Windows, ed25519-sk keys are supported in the [Termius](https://www.termius.com/) application, including the generation of resident keys. 

Please refer to [Yubico's documentation](https://developers.yubico.com/SSH/Securing_SSH_with_FIDO2.html) for more details on the setup and usage. 

- Command to create non-resident ed25519-sk keys:

```
ssh-keygen -t ed25519-sk -O application=ssh:key -f ~/.ssh/id_ed25519-sk_key
```

- Command to create resident ed25519-sk keys:

```
ssh-keygen -t ed25519-sk -O resident -O application=ssh:key -f ~/.ssh/id_ed25519-sk_key
```

- Command to export resident key to a new device:

```
ssh-keygen -K
```

All of the above commands will require you to prove presence to the hardware key as well as enter the PIN if configured. 

