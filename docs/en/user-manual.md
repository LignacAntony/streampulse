# User manual

> 🇫🇷 **Version française : [docs/manuel-utilisateur.md](../manuel-utilisateur.md)** — the
> French version is the reference.

This guide is for people who **use** StreamPulse, not those who develop it. No command, no
terminal: everything is done from the application.

It covers the three roles, in the order you meet them:

1. [Listener](#1-listener) — listen, add favourites, build a library
2. [Broadcaster](#2-broadcaster) — create a stream and broadcast live
3. [Administrator](#3-administrator) — manage accounts and moderate streams

**Related documents** — [accessibility.md](accessibility.md) (how to read this documentation
another way), [training-plan.md](training-plan.md),
[politique-confidentialite.md](../politique-confidentialite.md).

---

## Installing the application

The application is not yet published on a store. It installs directly from the file attached to
each release.

1. Open the project's releases page on GitHub.
2. Download the latest release's `.apk` file, from an **Android** phone.
3. Open the downloaded file. Android will ask for permission to install an application from
   outside the store: grant it for this one time.

> ⚠️ If the file name contains **`-NON-SIGNE`** (unsigned), it is a test build. It works, but it
> cannot later be updated by a final release: it has to be uninstalled first. This is not a
> precaution taken out of caution — it is an Android rule: it refuses to replace an application
> with another one signed differently.

**iOS**: the application cannot be distributed on iPhone. It works, but making it available
requires a paid Apple developer account, which the team does not have. Details are in
[distribution-mobile.md](../distribution-mobile.md).

## Reporting a problem

From the repository's **Issues** tab, choose **"Retour utilisateur"** (User feedback). The form
asks for the installed version — visible at the bottom of the **Profil** (Profile) screen.
Without it, a problem cannot be tied to a version, and it becomes very hard to know whether it
has already been fixed.

## Finding your way around the app

A bar at the bottom of the screen gives access to five spaces:

| Tab | What it's for |
|---|---|
| **Accueil** (Home) | Your favourites and what's live right now |
| **Bibliothèque** (Library) | Your tracks and playlists |
| **Découvrir** (Discover) | Browse every public live stream |
| **Tableau** (Dashboard) | Manage your own broadcasts — only useful to broadcasters |
| **Profil** (Profile) | Your account, your preferences, and administration for those entitled to it |

While something is playing, a **bar** appears just above this one. It stays visible whichever tab
you're on: playback does not stop when you navigate.

---

## 1. Listener

### 1.1 Creating an account

1. On opening the app, tap **"Créer un compte"** (Create an account).
2. Enter an email address, a username and a password, then confirm it.
3. Tick the consent checkbox. The words **"politique de confidentialité"** (privacy policy) and
   **"conditions d'utilisation"** (terms of use) are links: tapping them opens the document,
   which can be read before committing, then return to the form — what has already been entered
   is kept.
4. Tap **"Créer mon compte"** (Create my account). The button stays disabled until the box is
   ticked.

### 1.2 Logging in, and what to do if you forget your password

![StreamPulse home screen, Login tab selected](../captures/01-connexion.png)

**Textual equivalent.** The screen shows the name "StreamPulse" above a logo, and the tagline
"Redéfinissez votre expérience sonore." ("Redefine your sound experience."). Below it, two tabs
side by side: **Connexion** (Login, selected) and **Inscription** (Register). Then the **E-mail**
field, the **Mot de passe** (Password) field with an eye-shaped button to reveal what has been
typed, then the **"Mot de passe oublié ?"** (Forgot password?) link aligned to the right. The
**"Se connecter"** (Log in) button spans the full width. Further down, an "Ou" (Or) divider, two
third-party sign-in buttons, and finally **"Continuer en tant qu'invité"** (Continue as a guest),
which gives access to discovering public live streams without creating an account.

The login screen asks for the email and password.

If you forget it, tap **"Mot de passe oublié ?"** (Forgot password?) and enter your address. An
email arrives with a link; opening it from the phone switches straight into the application, on
the screen for choosing a new password.

> The message shown is the same whether or not the address exists. This is not a bug: it is what
> stops a third party from discovering who has an account.

### 1.3 Listening to a live stream

1. Open **Découvrir** (Discover). The list shows the public streams currently live, with their
   title and the broadcaster's name.
2. Tap a stream: playback starts and the player screen opens.
3. Going back does not interrupt anything — the playback bar takes over.

The bar offers **play/pause** and a **cross** to stop. Sound continues when the screen locks, and
the phone's controls (lock screen, headphones) work.

**If playback stops** — unstable network, a broadcaster who cuts the stream: the application
reconnects on its own, several times, spacing out the attempts. If the stream has genuinely
ended, it announces this and stops.

**When a live stream starts**, expect about ten seconds before the sound is available. The
application waits for you.

### 1.4 Adding a stream to favourites

From a stream's screen, tap the **star**. The stream joins the **Accueil** (Home) tab. Tapping it
again removes it. Favourites stay visible even when the stream is not live.

### 1.5 Adding your own tracks

1. **Bibliothèque** (Library) tab, then the add button.
2. Choose an audio file on the phone — MP3, AAC or OGG, **50 MB maximum**.
3. Give it a title (required); the artist is optional.
4. Confirm.

Each account has **500 MB**. Beyond that, the upload is refused with a clear message. A file that
is not really audio is refused even if its name ends in `.mp3` — the content is checked, not the
extension.

### 1.6 Creating and listening to a playlist

1. **Bibliothèque** (Library) tab, create a playlist and give it a name. Two playlists cannot
   share the same name.
2. Open it, add tracks from your library.
3. Reorder by dragging.
4. Tap **"Lire"** (Play) to listen from the start, or a track to start there.

While a playlist plays, the bar shows **previous / play / next**. Tapping it opens the full
queue, where you can jump to any track, drag the progress bar, and turn on:

- **Aléatoire** (Shuffle) — the playback order is randomised
- **Répétition** (Repeat) — three states: off, repeat track, repeat playlist

> The queue is a **snapshot** taken at launch. Reordering the playlist afterwards does not change
> what is currently playing: playback has to be restarted.

### 1.7 Requesting to become a broadcaster

**Profil** (Profile) tab → **"Devenir diffuseur"** (Become a broadcaster). Briefly explain what
you want to broadcast, then send. An administrator reviews the request; the status can be checked
in the same place. Once accepted, the **Tableau** (Dashboard) tab becomes useful.

---

## 2. Broadcaster

This chapter assumes the broadcaster role has been granted (§ 1.7).

### 2.1 Creating a stream

**Tableau** (Dashboard) tab → create a stream. Fill in:

- a **title** — several streams can share one
- a **description**, optional
- the **visibility**: *public* (visible in Discover) or *private* (visible to you only)

### 2.2 Getting your stream key

The stream's screen shows a **stream key** and a **source URL**. This is what you give to the
software that pushes the audio.

> ⚠️ **This key is authorisation to broadcast on your stream.** It is never visible to anyone
> else. Do not publish it, do not show it in a screenshot.

### 2.3 Broadcasting

1. Tap **"Démarrer"** (Start). The stream goes live.
2. Send the audio, in one of two ways:
   - **From the phone**: the application can capture the microphone directly.
   - **From broadcasting software**: configure it with the source URL.
3. Tap **"Arrêter"** (Stop) to end it. Listeners are notified that the stream ended and the
   player stops cleanly.

**Only one live stream at a time per broadcaster.** Trying to start a second one fails with a
clear message; stop the first one first.

The audio accepted is broad: if the format is not the expected one, it is converted on the fly.
Unreadable content is refused rather than broadcast broken.

### 2.4 Following your audience

While live, the stream's screen shows: the number of listeners, the **peak** reached, and the
elapsed duration.

> The listener count is an **estimate**. The broadcasting technology does not keep a permanent
> connection open: the server counts recent requests and infers an audience from them. The order
> of magnitude is right; the exact figure does not exist.

Off air, the counters are at zero.

### 2.5 Rotating a compromised key

If the key may have been seen by someone else: stream screen → **rotate the key**. The old one
stops working immediately.

**The stream must be stopped.** Rotating during a live broadcast is refused — the ongoing
broadcast relies on the old key.

---

## 3. Administrator

The administrator role cannot be requested from the application: it is granted directly in the
database. The tools appear in the **Profil** (Profile) tab, in a card visible only to
administrators.

### 3.1 Managing accounts

**Profil** (Profile) → **"Gestion des utilisateurs"** (User management).

- **Search** by email or username.
- **Filter** by role and by state (active or not).
- **Deactivate** an account: the person can no longer log in, and their current session drops
  within fifteen minutes at most. Nothing is erased, the action is reversible.
- **Delete** an account: **permanent**. The account, their streams, playlists, favourites and
  audio files disappear. Any of the person's ongoing broadcasts are stopped first.

Two actions are refused, with a message:

- deactivating or deleting yourself;
- removing the **last active administrator** — otherwise no one could administer the platform
  anymore.

### 3.2 Supervising and interrupting a live stream

**Profil** (Profile) → **"Supervision des flux"** (Stream supervision). The list shows **every**
live stream, public and private alike, with the broadcaster's identity.

The interrupt button stops a stream immediately, without going through its owner. Listeners are
disconnected cleanly.

Every interruption is recorded in the **audit log**: who, what, when. This trace survives even if
the administrator's account is deleted later — **without their identity**, which is then
detached.

### 3.3 Processing broadcaster role requests

**Profil** (Profile) → role requests. Each request shows the reason. **Accepting** promotes the
person immediately. **Rejecting** requires a note, sent to the requester.

---

## What to do if…

| Situation | What is happening | What to do |
|---|---|---|
| "Email ou mot de passe incorrect" (Incorrect email or password) | The pair matches no active account | Check the address; use "Mot de passe oublié ?" (Forgot password?) |
| Sound does not start on a live stream | The stream has just started — allow ~10 s | Wait; the application retries on its own |
| Playback stops on its own | Unstable network, or the end of the live stream | The application reconnects; if it is over, it says so |
| "Trop de tentatives" (Too many attempts) | Protection against repeated attempts | Wait a few seconds |
| A track upload is refused | File > 50 MB, the 500 MB quota is reached, or the file is not audio | The message states which |
| Cannot start a live stream | Another of your streams is already live | Stop it first |
| Cannot rotate the key | The stream is live | Stop it first |
| An opened stream returns "introuvable" (not found) | It is private, or deleted | Only its owner can access it |

---

## Deleting your account

**Profil** (Profile) → account deletion. The password is asked again: an unattended phone is not
enough to delete an account.

Deletion is **immediate and permanent**. What is erased, what is kept, and why:
[politique-confidentialite.md](../politique-confidentialite.md).

---

## Illustrations

This manual is **deliberately readable without images**: every journey is described using the
labels actually shown on screen, so that it stays usable by someone who cannot see the
screenshots — a screen reader, black-and-white printing, or reading from a terminal.

Screenshots live in [`captures/`](../captures/) and are **always paired with their textual
equivalent** in the corresponding section. A screenshot never introduces information that is
absent from the text: that is the rule that makes this document compliant with the accessibility
criteria declared in [accessibility.md](accessibility.md).

**Current state: only one screenshot has been produced** — the login screen (§ 1.2), taken on an
iPhone 17 simulator running iOS 26, with the application connected to a local API. Screenshots
for the remaining journeys require navigating the application, and therefore sending it taps; the
simulator's control tooling was not working during writing. The journeys are still described in
full by the text — that is exactly what the rule above guarantees.
