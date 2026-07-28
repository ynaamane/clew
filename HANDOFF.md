# HANDOFF — reprendre le projet dans ce repo

Contexte de construction (2026-07-23 → 07-27), écrit pour pouvoir reprendre le travail depuis ce dossier sans relire l'historique complet.

## Où en est le projet

**L'app a une fenêtre qui ne cache plus les échecs. 822 tests verts** (617 Python + 205 Swift, 4 sautés volontairement) + 6 tests matériel à la demande, HEAD `4be4e08`.

**⚠️ BUG5 était encore vivant jusqu'à aujourd'hui**, dans le binaire que le pipeline utilise réellement. Le correctif de juillet a atterri dans les sources Swift sans jamais atteindre la production : `coreaudio.py` préfère `bin/ownscribe-audio` à tout ce qui est dans `.build`, `bin/` est gitignored, et seul `swift/build.sh` y copie. Le binaire livré avait donc trois jours de retard sur le correctif et halvait toujours la vitesse de lecture. Mesuré sur une vraie capture double piste : `bin/` → **12,81 s @24000 Hz** depuis des sources à 48 kHz ; `.build/` → **5,52 s @48000 Hz**. La signature est dans tes réunions conservées — celles du 24 juillet sont à 24000 Hz. Corrigé dans `4be4e08` (rebuild + le test e2e résout le binaire via `_BINARY_CANDIDATES` et compare le taux fusionné à celui des sources + garde de péremption dans `check.sh`). **Tout enregistrement CLI d'avant aujourd'hui se lit à moitié vitesse — `./rec.sh redo <dir>` le refusionne correctement depuis les pistes conservées.** Leçon générale : demande quel artefact la production **charge**, pas celui que tu viens de construire.

**La fenêtre affiche enfin les échecs et l'avertissement de mute non confirmé** (`7c02399`). Bannière dans le rail en verre, jamais dans la couche contenu, avec la décision dans une fonction pure : une erreur passe devant l'avertissement de mute, et cet avertissement n'est **volontairement pas dismissible** — on ne doit pas pouvoir faire taire « le call peut encore t'entendre » pendant que c'est vrai. Leçon de méthode retenue au passage : la première version élargissait l'accès de `phase` pour permettre un test, ce qui est le motif interdit sous un autre nom, et trois de ses tests forçaient des états que la production ne peut pas produire. Après reprise, la mutation ne tue plus qu'**1** test sur 3 — c'est le chiffre honnête, pas un chiffre plus faible.

**Les deux vérifications de mute qui bloquaient tout sont faites — automatisées, pas déléguées.** Dès que les AirPods se sont déconnectés, le micro intégré est devenu le défaut, ce qui a écarté le seul cas non assertable (le bug Bluetooth documenté de macOS). `OWNSCRIBE_TEST_REAL_MUTE=1 swift test --filter RealHardwareMuteTests` → 3 tests verts sur le vrai périphérique : un mute que *tu* as fait survit au quit, un mute fait par l'app est défait au quit, et basculer via l'app en prend possession. Mutation-vérifié : retirer la garde `appOwnsMute` rend le test rouge sur du vrai matériel, et le micro était quand même restauré ensuite — c'est ce qui prouve que le teardown tient aussi sur le chemin d'échec.

**Il y a maintenant de vrais tests bout-en-bout, pas seulement unitaires.** `tests/test_real_capture_e2e.py` (5 tests, `@pytest.mark.hardware`) pilote le binaire `ownscribe-audio` livré. Les écrire a corrigé trois croyances fausses que 617 tests mockés laissaient passer : pas de flag `--duration` (il enregistre jusqu'au SIGINT), l'aide sort sur **stderr**, et il écrit du **float32 IEEE** que le `wave` de la stdlib refuse — d'où la lecture via `soundfile`. Ils jouent aussi du son pendant la capture, ce qui est essentiel : le tap enregistre ce que la machine **sort**, donc sur un système muet il produit correctement un en-tête valide à **zéro frame**. Ma première version captait ce silence et accusait le binaire.

**La suite de tests ne touche plus ton micro.** `swift test` dégradait l'audio de la machine : 0 cycle CoreAudio `PauseIO/ResumeIO` avant un run, **7920 après**, et l'entrée des AirPods Max bloquée à 24 kHz (profil HFP « téléphone ») au lieu de 48 kHz — ce qui étouffe le son de toutes les apps jusqu'à renégociation. Trois suites atteignaient le vrai périphérique d'entrée. Corrigé dans `e51000f`, un run complet mesure désormais **0 cycle**. La cause profonde vaut d'être retenue : injecter un point d'entrée sur `start()` ne suffisait pas, car `MicCapture` détient `AVAudioEngine` en propriété stockée — le périphérique est réservé à la **construction** de l'objet, pas à son démarrage. Le meter : `/usr/bin/log show --last 30s | grep -cE 'PauseIO|ResumeIO'` (chemin absolu obligatoire, une fonction zsh masque `log`).

**⚠️ `b0ce8db` est COMMITÉ MAIS PAS POUSSÉ, volontairement.** Il touche le mute système, et sa garantie centrale — l'app ne démute jamais un mute que tu as fait toi-même — n'est pas vérifiable sans matériel. Les deux tests qui décident sont dans `TODO.md` § « What W0-2/W0-3 changed ».

**Quatre bugs ouverts, trouvés le 2026-07-28**, tous de la même forme : une valeur câblée jusqu'à un consommateur jamais atteint. La fenêtre n'affiche ni les échecs ni l'avertissement de mute non confirmé (donc l'avertissement AirPods « le call peut encore t'entendre » n'apparaît nulle part) ; on peut enregistrer une réunion entière avant d'apprendre que rien ne peut la transcrire ; les filtres « Avec actions » / « Non ancrées » sont morts en production ; rien en Swift ne lit `envelope.json`. Aucun n'est détectable par une suite verte — c'est exactement pour ça qu'ils ont survécu. La collision d'audio dans la même minute est corrigée (`d626e72`), et le blocage de l'app + la fuite du tap ont été **réfutés** sur le code livré : la garde d'identité de run de `b0ce8db` les avait fermés par effet de bord.

**Leçon la plus coûteuse de la journée** (six tentatives sur un seul correctif) : quand plusieurs consommateurs lisent une même chaîne, le moins exigeant passe et c'est le plus exigeant qui décide. `MeetingSummary` dérive deux valeurs du nom de dossier — la date (`parts[1]` doit valoir exactement `HHmm`) et le titre (`parts[2]` = le slug). **Tous les noms candidats parsaient la date ; un seul préservait le titre**, donc chaque test aller-retour bâti sur la date passait sur toutes les mauvaises réponses. Avant de changer un format : énumérer ses consommateurs (`grep -rn lastPathComponent`), asserter sur la sortie de *chacun*, et sonder toute regex en cinq lignes — « ça parse » est nécessaire, jamais suffisant.

**Piège de diagnostic à connaître** (un handoff d'une autre session s'y est fait prendre le 28/07) : cinq SIGTRAP `xctest` ont été attribués à `EnrolledSpeakerStore.names(in:)`, avec un correctif recommandé sur du code qui n'a **aucun** défaut — la fonction n'a jamais contenu d'`assertionFailure` de toute son histoire. `_assertionFailure` est le symbole de trap générique de Swift ; la frame au-dessus était `Array._checkSubscript`, donc un index hors limites. Et les cinq crashs tournaient depuis `/private/tmp/*/ownscribe-audioPackageTests` — des copies isolées d'agents de revue, pas le dépôt, dont la suite était verte pendant tout ce temps. Vérifier le chemin du bundle qui crashe avant de toucher la production.

**⚠️ Une seule chose attend l'utilisateur : la fenêtre n'a jamais été vue.** Elle a 163 tests verts et zéro vérification visuelle — l'écran était en veille à chaque capture. `⌘0` depuis la barre de menus. Et le bundle installé date d'avant la fenêtre : relancer `bash swift/build-app.sh`.

**Design retenu : Glass** (direction B de `design/directions.html`), choisie après trois maquettes construites sur l'apparence réelle de ce Mac (mode sombre, accent violet) et sur l'enveloppe RMS réelle du call du 27 juillet — pas des barres inventées. Cible de déploiement montée à macOS 26 pour que Liquid Glass soit natif ; les 5 targets sont épinglés en mode langage Swift 5, car passer les outils en 6.0 a sorti 3 erreurs de concurrence stricte dans le code CoreAudio (chantier séparé).

**Le Swift a été audité indépendamment** (huit mutations, copie isolée). Le chemin de mute tient : indicateur figé sur « vérifié » → 1 rouge, boucle de démute au quit réduite à un essai → 1 rouge, suppression de la relecture verify-after-set → **6 rouges**. Chemins de sortie énumérés par grep, pas supposés — ⌘Q, force-quit et déconnexion passent tous par `willTerminateNotification`. Deux propriétés passaient 160 tests tout en étant remplaçables par une constante (`isRecording`, et le garde anti-double-comptage du parseur) : les deux sont désormais gardées. Détail dans `TODO.md` et `LESSONS_LEARNED.md`.

**Il n'y a plus de CI.** GitHub Actions n'a jamais réussi une seule fois (29 `startup_failure` à 0 s, repo privé, runner macOS facturé 10x). Remplacé par `bash scripts/check.sh` : 9 contrôles locaux dont la compile release.

**Une revue de code complète (2026-07-27) a fermé 11 findings réels sur 14.** Quatre relectures indépendantes ont tourné sur le même diff, et **chacune a trouvé ce que les trois autres avaient manqué**. La pire trouvaille est arrivée deux heures après que tout le monde ait déclaré le lot terminé : `silence_timeout` était câblé jusqu'au tap mais le callback n'atteignait personne — l'app ne s'arrêtait donc toujours jamais. Détail dans `TODO.md` § What the review changed.

**Deux leçons du 28 juillet, qui coûtent du temps si on les redécouvre.** (1) Un test qui exige un entrelacement précis sur un acteur sérialisé est le mauvais outil : vérifier que le pipeline qui se termine n'écrase pas l'enregistrement en cours a produit **deux blocages** de 23 min et 6 min, verrou SwiftPM tenu, deux autres agents bloqués — `AppState`, le faux runner et le corps XCTest sont tous `@MainActor` pendant que XCTest fait tourner une runloop sur ce thread. La sortie est d'extraire la DÉCISION de la chorégraphie : une fonction pure, 7 tests, 0,001 s. Un test qui se bloque est pire qu'un test qui échoue — il ne rapporte rien et bloque la machine : on le supprime, on ne le désactive pas. Repère utile : la suite entière tourne en ~38 s, donc au-delà de ~90 s ça bloque, et `lldb -p <pid> --batch -o "thread backtrace all"` nomme la cause en une commande. (2) Corriger un indicateur menteur peut créer un mensonge pire — semer `isMuted` depuis le matériel aurait fait démuter silencieusement au quit un mute fait dans Réglages Système.

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
