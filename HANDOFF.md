# HANDOFF — reprendre le projet dans ce repo

Contexte de construction (2026-07-23 → 07-27), écrit pour pouvoir reprendre le travail depuis ce dossier sans relire l'historique complet.

## Où en est le projet

**Code complet, zéro bug ouvert.** 655 tests verts (563 Python + 92 Swift). Tout sur `main`, poussé sur le repo privé `ynaamane/meeting-scribe`. Il ne reste que la passe matériel côté utilisateur — voir `TODO.md` § YOUR TURN.

## Comment on est arrivé là (décisions et pourquoi)

Point de départ : remplacer Spark AI par une solution locale, fiable, avec diarisation, sur Mac, FR+EN.

Décisions tranchées par débat adversarial (BMAD) + recherche cross-vérifiée, puis par un pilote empirique :

- **Fork `paberr/ownscribe`** plutôt que greenfield — il apportait déjà la capture macOS + le pipeline whisperx/pyannote. Construire de zéro était de la sur-ingénierie.
- **Whisper large-v3**, pas turbo, pas Parakeet, pas Canary. Turbo est plus faible en FR. Parakeet n'a aucun conditionnement de langue → il **traduit involontairement** le français spontané en anglais (falsification silencieuse, disqualifiant). Canary était un vrai candidat A/B (il a `source_lang`) mais le **pilote sur audio réel code-switché l'a fait perdre de 66 points** sur les spans de bascule → whisperx reste défaut.
- **Capture = CoreAudio process tap** (macOS 14.2+), pas ScreenCaptureKit : SCK exige la permission « Enregistrement d'écran » même pour de l'audio seul, ce qui contredisait l'exigence « audio uniquement ». Le tap utilise la permission audio-only. SCK gardé en fallback <14.2.
- **Ta voix vs le call = deux sources physiques**, pas de la diarisation : ton micro (ce que tu envoies) = `mic.wav` = « Owner » ; le tap système (ce que tu reçois) = `system.wav` = diarisé. Séparation parfaite par construction — mais seulement **au casque** (sur haut-parleurs, l'audio du call re-rentre dans le micro → `echo_cancellation`).
- **Diarisation pyannote community-1 sur CPU**, jamais MPS. De toute façon tout le chemin ASR est CPU-bound (CTranslate2 n'a pas de backend Metal), donc forcer CPU ne coûte rien.
- **Nommage réutilise les embeddings par cluster de pyannote** — aucune dépendance ECAPA/SpeechBrain ajoutée.
- **Mute maître système** via `kAudioDevicePropertyMute` avec **verify-after-set obligatoire** : on relit l'état, et on ne dit « muté » que si la relecture confirme. C'est ce qui attrape le bug macOS documenté sur AirPods (le mute atterrit sur la sortie au lieu de l'entrée) sans avoir à traiter le Bluetooth comme un cas spécial.
- **Canary isolé en subprocess** (`uv run --with mlx-audio`) : mlx-audio exige `huggingface-hub>=1.0`, whisperx le cape `<1.0` — conflit irréductible, aucun fix par config ne marche. Le venv de base reste bit-identique.

## Les bugs qui comptent (détail complet dans `LESSONS_LEARNED.md`)

Trouvés par des runs RÉELS, pas par des tests synthétiques :

- **BUG0 (critique)** — le tap a **gelé Zoom** au point de ne plus pouvoir rejoindre un call ; Ctrl+C libérait instantanément. Cause : aucun Info.plist embarqué → pas de `NSAudioCaptureUsageDescription` → macOS n'avait rien à afficher comme prompt → le tap non autorisé bloquait CoreAudio ~60s, gelant tous les clients audio. Un test sur tonalité synthétique n'aurait jamais pu l'attraper.
- **13 Go / 38,9 h de sortie depuis 3 s de capture** (pré-existant dans ownscribe) — un fichier temp sans chunk `data` alimentait un compte de frames corrompu.
- **BUG2** — le résumé LLM **inventait** des noms et des engagements absents de l'audio. Dangereux sur un compte-rendu pro.
- **BUG3** — offset mic↔système de -28,3 s → l'ordre chronologique du transcript cassé. La cause n'était PAS le calcul d'offset (triangulé 3 fois) mais le merge qui ne gérait que les offsets positifs.
- **Le mute pouvait te laisser muté** — le démute automatique ne se déclenchait que via un bouton précis du menu ; Cmd+Q, force-quit ou une extinction laissaient le micro système coupé, silencieusement. Trouvé par le reviewer indépendant en grepant tous les chemins de sortie.

## Hygiène de travail (règle permanente, voir `CLAUDE.md`)

TDD test-first (rouge → vert, transition rapportée), reviewer **indépendant** qui re-exécute les preuves au lieu de lire le diff, scrutin renforcé sur le code à fort blast radius (mute système, tap CoreAudio), et « vérifie, ne suppose pas » — le disque et `git log` sont la vérité, pas un message disant « c'est fait ».

Cette boucle a attrapé, entre autres : une preuve de vérification inexacte, un faux négatif de test (venv qui shadow-importait le repo principal), deux violations de la règle no-comments, un test qui dormait 3,2 s, et une commande erronée dans la checklist de test elle-même.

## Points ouverts / pièges connus

- Le **raccourci global ⌘⇧M** n'a qu'**une** confirmation en conditions réelles (la re-vérification a été bloquée par l'écran en veille, qui empêche l'injection de touches). À valider sur matériel réveillé.
- **AirPods** : le mute système y est le cas fragile (bug macOS documenté). Le garde-fou avertit si la relecture échoue — si tu vois l'avertissement, c'est le garde qui fonctionne, pas une panne.
- **Le cas salle de réunion** (N personnes sur un seul canal Zoom) a un **plafond physique** : une fois les voix sommées en mono, la parole simultanée n'est pas récupérable. L'extraction de locuteur cible (VoiceFilter & co) a été évaluée et écartée : mauvaise direction (elle extrait la cible et supprime les autres), mesurée sur de l'anglais lu propre, et sans artefact déployable sur Mac/FR.
- Ne **jamais supprimer** le certificat de signature une fois créé : un cert recréé = nouvelle identité = macOS réinitialise toutes les permissions.

## Fichiers à lire en priorité

`TODO.md` (état + les 3 étapes restantes) · `CLAUDE.md` (règles projet + hygiène) · `LESSONS_LEARNED.md` (journal des bugs) · `APP_TEST.md` (checklist matériel) · `BUILD.md` (cert + build de l'app) · `NOTES.md` (détails d'implémentation).
