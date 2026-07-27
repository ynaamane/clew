# HANDOFF — reprendre le projet dans ce repo

Contexte de construction (2026-07-23 → 07-27), écrit pour pouvoir reprendre le travail depuis ce dossier sans relire l'historique complet.

## Où en est le projet

**Zéro bug ouvert. L'app a une fenêtre.** 773 tests verts (610 Python + 163 Swift), HEAD `e793000`, tout poussé.

**⚠️ Une seule chose attend l'utilisateur : la fenêtre n'a jamais été vue.** Elle a 163 tests verts et zéro vérification visuelle — l'écran était en veille à chaque capture. `⌘0` depuis la barre de menus. Et le bundle installé date d'avant la fenêtre : relancer `bash swift/build-app.sh`.

**Design retenu : Glass** (direction B de `design/directions.html`), choisie après trois maquettes construites sur l'apparence réelle de ce Mac (mode sombre, accent violet) et sur l'enveloppe RMS réelle du call du 27 juillet — pas des barres inventées. Cible de déploiement montée à macOS 26 pour que Liquid Glass soit natif ; les 5 targets sont épinglés en mode langage Swift 5, car passer les outils en 6.0 a sorti 3 erreurs de concurrence stricte dans le code CoreAudio (chantier séparé).

**Il n'y a plus de CI.** GitHub Actions n'a jamais réussi une seule fois (29 `startup_failure` à 0 s, repo privé, runner macOS facturé 10x). Remplacé par `bash scripts/check.sh` : 9 contrôles locaux dont la compile release.

**Une revue de code complète (2026-07-27) a fermé 11 findings réels sur 14.** Quatre relectures indépendantes ont tourné sur le même diff, et **chacune a trouvé ce que les trois autres avaient manqué**. La pire trouvaille est arrivée deux heures après que tout le monde ait déclaré le lot terminé : `silence_timeout` était câblé jusqu'au tap mais le callback n'atteignait personne — l'app ne s'arrêtait donc toujours jamais. Détail dans `TODO.md` § What the review changed.

Leçon de méthode qui vaut pour la suite : **trois des tests écrits pour ces corrections ne pouvaient pas échouer** (un `XCTAssert(true)` nu, un espion asserté au lieu du processus enfant, une comparaison `phase == .recording(startedAt: Date())` fausse dans tous les cas). Une suite verte n'est pas une preuve. Casser ce qu'un test défend et le voir rougir, si.

**Éprouvée sur un vrai call de 17,5 min** (2026-07-27, réunion de travail bilingue sur Google Meet dans Dia) : le tap a tenu tout le call malgré des changements d'app et des coupures réseau, zéro minute silencieuse, 3 locuteurs séparés, résumé factuel. Mais ce call a tourné sur un bundle antérieur au fix BUG4, donc il n'a capté que les autres participants — la voix du propriétaire n'y est pas.

Il reste la passe matériel côté utilisateur — voir `TODO.md` § YOUR TURN.

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

## Ce que le token et le build ne demandent plus

- **Le token HF n'est plus à exporter.** Il vit dans `~/.config/ownscribe/config.toml` (chmod 600, hors du repo) pour le CLI, et dans le Keychain login (`com.ownscribe.menubar` / `hf_token`) pour l'app. `export HF_TOKEN=...` reste un override ponctuel.
- **`swift/build-app.sh` installe lui-même dans `/Applications`** et échoue si le binaire installé diffère de celui buildé. Raison : un call de 17 min a été enregistré contre un bundle périmé parce que builder et installer étaient deux gestes manuels séparés.

## Performance — le levier trouvé

whisperx impose `threads=4` par défaut (`asr.py:329`) et le code ne le surchargeait pas : sur un M4 Max à 12 cœurs performance, un quart de la machine travaillait. La transcription se dimensionne maintenant sur `hw.perflevel0.physicalcpu`. Mesuré sur 90 s du vrai call : **30,9 s → 20,5 s, transcript identique au mot près**. Contre-intuitif : 16 threads est PIRE (23-25 s), les 4 cœurs d'efficacité freinent le lot.

La diarisation est désormais l'étape la plus chère (0,63x temps réel contre 0,33x pour l'ASR). Le détail des pistes ouvertes (FluidAudio, turbo, mlx-whisper) et des mesures est dans `TODO.md` § Performance.

## Points ouverts / pièges connus

- Le **raccourci global ⌘⇧M** n'a qu'**une** confirmation en conditions réelles (la re-vérification a été bloquée par l'écran en veille, qui empêche l'injection de touches). À valider sur matériel réveillé.
- **AirPods** : le mute système y est le cas fragile (bug macOS documenté). Le garde-fou avertit si la relecture échoue — si tu vois l'avertissement, c'est le garde qui fonctionne, pas une panne.
- **Le cas salle de réunion** (N personnes sur un seul canal Zoom) a un **plafond physique** : une fois les voix sommées en mono, la parole simultanée n'est pas récupérable. L'extraction de locuteur cible (VoiceFilter & co) a été évaluée et écartée : mauvaise direction (elle extrait la cible et supprime les autres), mesurée sur de l'anglais lu propre, et sans artefact déployable sur Mac/FR.
- Ne **jamais supprimer** le certificat de signature une fois créé : un cert recréé = nouvelle identité = macOS réinitialise toutes les permissions.

## Fichiers à lire en priorité

`TODO.md` (état + les 3 étapes restantes) · `CLAUDE.md` (règles projet + hygiène) · `LESSONS_LEARNED.md` (journal des bugs) · `APP_TEST.md` (checklist matériel) · `BUILD.md` (cert + build de l'app) · `NOTES.md` (détails d'implémentation).
