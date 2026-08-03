# HANDOFF — reprendre le projet dans ce repo

Contexte de construction (2026-07-23 → 08-03), écrit pour pouvoir reprendre le travail depuis ce dossier sans relire l'historique complet.

## Session 2026-08-03 (suite) — premier VRAI appel vérifié bout en bout, 3 voix enrôlées

Le premier appel réel (`2026-08-03_1401_pptx-tool-bug-review-update`, 32:45, fr, en salle avec
Devon, Kamal en 3ᵉ voix) a traversé toute la chaîne sans intervention : pistes alignées à 26 ms,
48 kHz partout, transcript complet, titre passé le garde anti-refus, 5 tokens d'ancres, envelope
96 % active, pipeline ~1× temps réel. Le mute SYSTÈME de Yanis a produit un `mic.wav` en zéro
numérique après 6 s — gate RMS impeccable ; l'unique tour Owner est l'hallucination Whisper
canonique sur quasi-silence (« Sous-titrage Société Radio-Canada », filtre à construire).

**Enrollment fait depuis l'appel lui-même, sans enregistrement neuf** : Yanis identifié par
forensique contextuel + voix — **la première lecture (SPEAKER_01=Yanis) était FAUSSE**, réfutée
par un vocatif au milieu d'un monologue voix-cohérent (règle : un vocatif EXCLUT son locuteur,
une réponse ne fait que suggérer ; les deux indices contradictoires étaient la première et la
dernière ligne de l'enregistrement). Devon/Kamal départagés par UN fait physique fourni par
Yanis (Devon dans la salle = le cluster qui matche le mic à 0.777). Matrice 3×3 sur segments
témoins : diagonale 0.957/0.725/0.863, pire croisement **0.637 (marge 0.013 sous le seuil)** →
c'est l'argument des prints multi-échantillons. Vérifié dans l'app VIVANTE par AX tree : la
sidebar Personnes affiche Yanis/Devon/Kamal. Prochains meetings auto-nommés ; celui du jour
reste en SPEAKER_NN sauf `reprocess` explicitement demandé (réécrit transcript/summary, ~30 min).

Défaut réel trouvé en regardant : badge « 1 action » sur un meeting dont le summary dit
« Action Items: None mentioned. » (le parseur compte le bullet). Designs validés par Yanis :
auto-suggest enrollment avec **confirmation in-app obligatoire**, et règles anti-overlap
(clips mi-run seulement, chevauchement affiché comme incertitude). **La reprise se fait par
`TODO.md` § BUILD NEXT** — 9 items ordonnés, designs complets dans les paragraphes en dessous.

## Session 2026-08-03 — l'audit 4 lanes puis le batch design, e2e fermé par les agents

Déclencheur : « le design n'est pas bon » — et l'audit a montré que le verdict avait été rendu
sur un bundle périmé de 22 commits UI, sur des réunions sans données d'ancrage. Trois causes
empilées, toutes fermées le jour même. Livré (commits `851aede`→`1830b0b`) : verre sur les
conteneurs des 3 surfaces avec tests qui épinglent le **receveur** du modificateur (deux bugs
attrapés par revue croisée : un receveur changé sans que la ligne bouge, un matcher littéral
aveugle aux appels à arguments) ; tours de parole groupés ; rail inspecteur plat + ratio N/M ;
callout d'ancrage ; pilule interventions courtes ; méta de rangées ; accent violet
(`AppAccentColor`) ; sous-titre ; garde anti-refus Python structurel testé dans les deux sens ;
commande `ownscribe backfill` **exécutée en réel** (le 27-juil. a 9 tokens d'ancres : Lambda@05:09,
Gary@08:30, JWT@05:28 — la scène exacte de la maquette, vérifiée sur capture de la vraie fenêtre).
Chiffres au moment du dernier check.sh de la session (re-mesure-les, règle ci-dessous) :
479 XCTest + 47 swift-testing, 676 Python (1 skipped, 7 deselected), CHECK=0, 10/10.

Trois directives/faits nouveaux à connaître avant de reprendre :
- **« Aucune action n'est interdite aux agents »** (Yanis, 2026-08-03) : les agents font l'e2e
  complet, `build-app.sh` compris. Invariants conservés : ne jamais recréer/supprimer le cert de
  signature ; capture de la fenêtre seule, jamais l'écran ; `~/ownscribe/` en ADD-only ;
  restaurer tout état système modifié.
- **La sélection de liste suit l'accent SYSTÈME** (vert sur cette machine), pas le `.tint` —
  c'est macOS, pas un bug ; le violet s'applique aux puces/liens.
- **Réunions en salle** : la salle rejoint Zoom aussi → les voix de la salle passent par
  `system.wav` et sont diarisables/nommables. Règles : rejoindre AVEC l'audio ordinateur ;
  enrôler sa propre voix ; couper `mic.wav` avec le mute de l'APP — **le mute Zoom n'arrête pas
  la capture micro de l'app**. Détail : TODO item 10. ~~Enrôlement toujours à faire (0
  empreinte).~~ Fait le soir même — voir le bloc de session au-dessus (3 empreintes vérifiées).

## Où en est le projet

**637 Python + 468 Swift verts**, toutes les portes de `scripts/check.sh` au vert (`CHECK=0`,
0 porte en échec), plus les tests matériel à la demande. Mesuré le **2026-07-31 en fin de
session** — mais ne crois pas ce nombre, re-mesure-le : il a été faux dans ce fichier cinq fois,
et « écrire le nombre » est une étape distincte de « le mesurer » qui se rate seule. De même pour
« tout est poussé » : lance `git log --oneline origin/main..main | wc -l`. Un fait mutable
appartient à une commande, pas à une phrase.

Le compte Swift demande d'additionner **deux** frameworks : `swift test` imprime un total XCTest
(`Executed 431 tests, with 9 tests skipped` → 422 qui passent) *et* une ligne séparée
`Test run with 46 tests` pour swift-testing. Tout « 276 Swift », « 343 Swift », « 413 Swift »,
« 431 Swift », « 448 Swift » ou « 458 Swift » plus haut dans l'historique ne comptait que XCTest, ou datait
d'avant les derniers lots.
Ne lis jamais le total via `tail` : ça tronque le résumé, et dans une redirection `> fichier` ça
détruit le chiffre sur le disque. Un échec peut n'apparaître que dans **un** des deux formats :
le 2026-07-30 une vraie mutation tuée affichait « Executed 0 tests » côté XCTest pendant que le
rouge était côté swift-testing.

**Les deux totaux bougent d'un run à l'autre pour des raisons d'ENVIRONNEMENT, pas de code** —
sachez-le avant de crier à la régression. Les 9 sauts Swift comprennent les tests matériel
(`RealHardwareMuteTests`, `RecordingControllerMergeFailureTests`) **et** le nouveau
`DesignRenderTests`, qui est volontairement derrière `OWNSCRIBE_RENDER_UI=1`. Et Python affiche
`637 passed, 1 skipped` ou `638 passed` selon que `/tmp/ms-fixture` existe :
`tests/test_anchoring_context_contains_token.py:24` se saute lui-même quand la fixture de la vraie
réunion a été effacée par un nettoyage de `/tmp`. Un chiffre Python sans son invocation ET sans
l'état de `/tmp` ne veut rien dire.

Lis le code de sortie depuis une **variable capturée**, jamais au bout d'un pipeline : deux fois
le harness a annoncé « exit 0 » alors qu'une porte avait ÉCHOUÉ dans la sortie — la porte
anti-péremption de BUG5 (`bin/ownscribe-audio` plus vieux qu'un source Swift), que
`bash swift/build.sh` referme. Elle saute à **chaque** édition Swift, y compris menu-bar.

Après le run complet : `/usr/bin/log show --last 10m | grep -cE 'PauseIO|ResumeIO'` → **0**.
Aucun test n'a touché le micro.

## Ce qui a changé le 2026-07-31 (à lire en premier)

**Les sept items de code sont fermés**, chacun mutation-vérifié. Il reste **deux** choses, et
aucune ne se ferme en écrivant du code ici : ton œil sur la fenêtre (le verre rend des octets
identiques avec ou sans lui hors-écran, donc il n'a qu'un seul juge possible), et un vrai
enregistrement pour la puce de preuve cliquable.

- **Le champ de recherche est une décision, pas un patch** — et le SDK a tranché ce que les pixels
  suggéraient : `SearchToolbarBehavior.minimize` est `@available(macOS, unavailable)`, donc
  `.automatic` est la seule valeur que la plateforme accepte. Il n'y a jamais eu de levier. La
  décision est épinglée dans un test plutôt que laissée en prose, là où elle allait être
  re-débattue une troisième fois.
- **Le bandeau CLI**, 200 caractères dans un rail de 216pt, est devenu un titre de 39 caractères
  plus le texte de récupération, en français. La première correction rendait `headline ?? message`,
  ce qui rendait `./rec.sh redo` **inatteignable** alors qu'un test au niveau des données restait
  vert : la chaîne existait dans la struct et aucun chemin de vue ne l'affichait. Même forme que
  `UnanchoredClaimBadge` livré avec 4 tests verts et zéro appelant.
- **`cancel()` est enfin appelé.** Une transcription de plusieurs minutes s'arrête. Refusé pendant
  `.recording` — une réunion en cours est irremplaçable — et sans effet depuis un état terminal.
  `cancel()` est passé sur le protocole `PipelineRunning` : le `as? PipelineRunner` compilait et
  rendait l'appel **inobservable** par tous les fakes, donc un espion aurait prouvé que la phase
  changeait pendant que le process enfant continuait à transcrire.
- **10 identifiants d'accessibilité** là où il y en avait 0. Une revue peut désormais *adresser*
  les contrôles, pas seulement lire du texte. Le bouton d'enregistrement était le cas à réfléchir :
  son titre change avec l'état (Enregistrer / Arrêter), donc l'adresser par titre le perd au moment
  précis où on voudrait appuyer sur stop.
- **La colonne de `—` nus** de l'inspecteur devient `(aucune correspondance)`, avec les trois états
  d'ancrage gardés comme deux-à-deux distincts et non vides.
- **Le chemin SIGTERM vers l'unmute est enfin gardé** — l'item le plus à risque du lot : un échec
  laisse le micro de l'utilisateur coupé pour tout le système, silencieusement, après la mort du
  process. `TerminationSignalHandlers` injecte les trois effets (`makeSource`,
  `ignoreDefaultDisposition`, `onTerminate`), donc aucun test ne lève un vrai signal ni ne tue le
  runner. Trois propriétés qui échouaient **silencieusement** sont épinglées : les sources doivent
  être **retenues** (un `DispatchSourceSignal` désalloué ne délivre plus rien, donc supprimer le
  tableau tue le chemin avec toute la suite au vert), la disposition doit être ignorée **avant** le
  resume, et l'unmute doit passer **avant** le terminate. Le garde de propriété est épinglé sur ce
  chemin aussi : un mute que l'UTILISATEUR a fait dans Réglages Système survit à un SIGTERM.
  Mutations 6/6. Le design des tests vient d'une lane qui a écrit la moitié ROUGE puis s'est
  arrêtée — état à reconnaître : `swift build` était **vert** pendant que
  `swift build --build-tests` échouait, donc la suite entière était injouable alors qu'un build de
  sources seules annonçait le succès.

Deux erreurs de process de ma part, notées parce qu'elles se répètent facilement :
`git commit --amend` dans cet arbre partagé a réécrit le message de commit d'une lane voisine
(HEAD avait bougé entre-temps ; restauré par `reset --soft`), et un chiffre de mutation est parti
dans un message de commit par raisonnement au lieu d'être mesuré. Les deux sont maintenant dans
`.claude/skills/swift-suite-hygiene/SKILL.md`.

## Ce qui a changé le 2026-07-30

**Je peux enfin voir la fenêtre moi-même, sans action de l'utilisateur.** C'était le blocage
central de tout ce projet : chaque revue de design dépendait d'un humain avec une souris.

- **Les permissions étaient DÉJÀ accordées** — `AXIsProcessTrusted()` → `true`,
  `screencapture -l` produit un PNG. Rien à activer. Le blocage était **l'app**.
- **Il n'existait aucune route pour ouvrir la fenêtre sans clic.** Le popover
  `MenuBarExtra(.window)` de SwiftUI n'expose RIEN à l'accessibilité (`AXPress` réussit, le
  sous-arbre est juste `AXMenuBarItem "Audio Waveform"`), aucun `CFBundleURLTypes`, et `⌘0`
  était déclaré sur un `Button` **à l'intérieur** du popover donc inerte quand il est fermé.
  C'était aussi un vrai trou d'accessibilité clavier.
- **Corrigé** (`7a3abf2`) : `open "ownscribe://library"` ouvre la fenêtre, plus une commande de
  menu portant `⌘0` au niveau app. Le handler est installé via `NSAppleEventManager` au niveau
  AppKit — un `.onOpenURL` sur une scène n'existerait que pendant que la scène est rendue, soit
  le même piège une couche plus haut.
- **L'outil de revue** : `bash scripts/ui-evidence/capture.sh MeetingScribe /tmp/ui-ev` →
  screenshot **ciblé sur la fenêtre** + arbre d'accessibilité. Il résout le window-id **par
  propriétaire** puis le passe à `screencapture -l`, donc il ne peut structurellement pas
  capturer l'écran (la seule tentative plein écran avait attrapé du contenu confidentiel).
  Note : `screencapture -l` échoue si la fenêtre n'est pas au premier plan — activer l'app d'abord.

**⚠️ ET LA BOUCLE CI-DESSUS EXIGE UN ÉCRAN DÉVERROUILLÉ — elle a été bloquée le jour même.**
`ioreg -n Root -d1 -r | grep CGSSessionScreenIsLocked` → `Yes` : la fenêtre existe mais se déclare
`onscreen=no`, son compte `AXWindow` tombe à **0**, et `screencapture -l` la refuse. Une boucle
« autonome » qui exige quelqu'un devant la machine ne l'est pas.

**Le remplaçant fonctionne écran verrouillé** :

```bash
bash scripts/ui-evidence/render.sh /tmp/ui-render   # library-light.png + library-dark.png
```

Un `NSWindow` hors-écran + `NSHostingView` + `cacheDisplay`, dans la cible de TEST pour pouvoir
faire `@testable import OwnscribeMenuBar` (la voie `swiftc` autonome bute sur un timeout du
type-checker et pousse vers une réplique écrite à la main — exactement comme un harnais finit par
valider un design que l'app n'a pas). Capture `contentView.superview` (**NSThemeFrame**), sinon la
barre de titre et tout le champ de recherche sont absents de l'image.

**Connais ses angles morts avant de lui faire confiance** — ils sont imprimés à chaque run et
détaillés dans `APP_TEST.md` : `glassEffect` rend des octets **identiques** avec verre,
sans verre et verre-sur-conteneur (un seul md5 pour les trois), et la ligne sélectionnée est
peinte en noir opaque **par-dessus son icône, son libellé et son badge** — donc un badge présent
dans l'app est absent du rendu. Ne certifie jamais le verre ni un matériau sur un rendu.
Voie morte mesurée, ne pas réessayer : `ImageRenderer` dessine `List` en carré jaune d'interdiction.

**⚠️ LE DESIGN N'EST TOUJOURS PAS VALIDÉ, mais la liste a beaucoup changé : QUATRE des sept
écarts étaient FAUX.** Détail dans `TODO.md § 0`. Le premier, classé priorité 1 — « la fenêtre est
claire, la maquette est sombre » — était un fait sur **la machine** : elle est en mode clair,
l'app n'a aucun `preferredColorScheme`, donc elle obéissait correctement, et « corriger » aurait
écrasé le réglage auto de l'utilisateur. Deux autres (avatars, bande d'enveloppe) étaient déjà
codés et invisibles parce qu'**aucune réunion n'était sélectionnée** : rien ne rendait dans cette
colonne. Le seul écart qui a survécu est celui qui a été **REPRODUIT**, pas seulement vu.

**Regarder est nécessaire et ne suffit pas.** Une capture superpose un état système et un état de
code, et ne dit pas lequel produit quoi. Avant de coder sur un constat visuel, nomme le mécanisme.

Ce que l'arbre AX donne, contrairement à ce que ce fichier disait : **55 lignes**, avec le texte de
chaque ligne et ses cadres en pixels (`@433,322 174x16`) — de quoi mesurer l'espacement. Ce qui
manque, c'est `.accessibilityIdentifier` sur les vues *interactives*, donc on peut LIRE les
éléments mais pas les ADRESSER de façon stable.

## L'historique de la faute sur le design (gardé, parce qu'elle a été commise deux fois)

**Rejeté par l'utilisateur le 2026-07-28 après avoir ouvert l'app.**

Et la manière dont cette ligne est arrivée là compte plus que le design lui-même, parce que
**la même faute a été commise deux fois dans la même journée**.

Round 1 : `TODO.md` affirmait le design Glass livré, sur la foi de « standard components carry
Liquid Glass automatically ». La cible de déploiement avait bien été montée à macOS 26, et on en
avait déduit que Glass arrivait gratuitement. Faux : ce que la maquette appelle Glass est une
**mise en page** — avatars, bande d'enveloppe, échelle typo HIG, verre sur les rails. L'utilisateur
a ouvert l'app et l'a vu en secondes.

Round 2, le 2026-07-28 en fin de journée : le travail d'apparence était fait (`82ed390`, 3 sites
`glassEffect`, jamais sur le transcript — la HIG l'interdit dans la couche contenu), la suite était
verte à 262, et la ligne de statut a été réécrite en « la fenêtre ressemble enfin au design validé »
— **sans que personne ait regardé**. Rejeté sur le champ.

La faute n'est pas une négligence sur un fait, c'est d'avoir **substitué la preuve disponible à la
preuve requise**. Une suite verte, 3 appels `glassEffect`, un symbole présent dans le binaire :
tout ça prouve que le code TOURNE. Rien n'est une preuve sur la façon dont il se LIT. Quand la
seule réponse honnête est « personne n'a regardé », il faut l'écrire. Et corriger une
affirmation-sans-preuve par une *autre* affirmation-sans-preuve n'est pas une correction.

**Ce qu'on ne sait PAS encore :** quelle partie du design est mauvaise. « Pas bon du tout » est un
verdict global, donc l'étape suivante est de regarder la fenêtre AVEC l'utilisateur, pas de deviner
un espacement ou une couleur et d'itérer à l'aveugle contre une cible que personne n'a vue.

**⚠️ BUG5 était encore vivant jusqu'au 2026-07-28**, dans le binaire que le pipeline utilise réellement. Le correctif de juillet a atterri dans les sources Swift sans jamais atteindre la production : `coreaudio.py` préfère `bin/ownscribe-audio` à tout ce qui est dans `.build`, `bin/` est gitignored, et seul `swift/build.sh` y copie. Le binaire livré avait donc trois jours de retard sur le correctif et halvait toujours la vitesse de lecture. Mesuré sur une vraie capture double piste : `bin/` → **12,81 s @24000 Hz** depuis des sources à 48 kHz ; `.build/` → **5,52 s @48000 Hz**. La signature est dans tes réunions conservées — celles du 24 juillet sont à 24000 Hz. Corrigé dans `4be4e08` (rebuild + le test e2e résout le binaire via `_BINARY_CANDIDATES` et compare le taux fusionné à celui des sources + garde de péremption dans `check.sh`). **Tout enregistrement CLI d'avant le 2026-07-28 se lit à moitié vitesse — `./rec.sh redo <dir>` le refusionne correctement depuis les pistes conservées.** Leçon générale : demande quel artefact la production **charge**, pas celui que tu viens de construire.

**La fenêtre affiche enfin les échecs et l'avertissement de mute non confirmé** (`7c02399`). Bannière dans le rail en verre, jamais dans la couche contenu, avec la décision dans une fonction pure : une erreur passe devant l'avertissement de mute, et cet avertissement n'est **volontairement pas dismissible** — on ne doit pas pouvoir faire taire « le call peut encore t'entendre » pendant que c'est vrai. Leçon de méthode retenue au passage : la première version élargissait l'accès de `phase` pour permettre un test, ce qui est le motif interdit sous un autre nom, et trois de ses tests forçaient des états que la production ne peut pas produire. Après reprise, la mutation ne tue plus qu'**1** test sur 3 — c'est le chiffre honnête, pas un chiffre plus faible.

**Les deux vérifications de mute qui bloquaient tout sont faites — automatisées, pas déléguées.** Dès que les AirPods se sont déconnectés, le micro intégré est devenu le défaut, ce qui a écarté le seul cas non assertable (le bug Bluetooth documenté de macOS). `OWNSCRIBE_TEST_REAL_MUTE=1 swift test --filter RealHardwareMuteTests` → 3 tests verts sur le vrai périphérique : un mute que *tu* as fait survit au quit, un mute fait par l'app est défait au quit, et basculer via l'app en prend possession. Mutation-vérifié : retirer la garde `appOwnsMute` rend le test rouge sur du vrai matériel, et le micro était quand même restauré ensuite — c'est ce qui prouve que le teardown tient aussi sur le chemin d'échec.

**Il y a maintenant de vrais tests bout-en-bout, pas seulement unitaires.** `tests/test_real_capture_e2e.py` (5 tests, `@pytest.mark.hardware`) pilote le binaire `ownscribe-audio` livré. Les écrire a corrigé trois croyances fausses que 617 tests mockés laissaient passer : pas de flag `--duration` (il enregistre jusqu'au SIGINT), l'aide sort sur **stderr**, et il écrit du **float32 IEEE** que le `wave` de la stdlib refuse — d'où la lecture via `soundfile`. Ils jouent aussi du son pendant la capture, ce qui est essentiel : le tap enregistre ce que la machine **sort**, donc sur un système muet il produit correctement un en-tête valide à **zéro frame**. Ma première version captait ce silence et accusait le binaire.

**La suite de tests ne touche plus ton micro.** `swift test` dégradait l'audio de la machine : 0 cycle CoreAudio `PauseIO/ResumeIO` avant un run, **7920 après**, et l'entrée des AirPods Max bloquée à 24 kHz (profil HFP « téléphone ») au lieu de 48 kHz — ce qui étouffe le son de toutes les apps jusqu'à renégociation. Trois suites atteignaient le vrai périphérique d'entrée. Corrigé dans `e51000f`, un run complet mesure désormais **0 cycle**. La cause profonde vaut d'être retenue : injecter un point d'entrée sur `start()` ne suffisait pas, car `MicCapture` détient `AVAudioEngine` en propriété stockée — le périphérique est réservé à la **construction** de l'objet, pas à son démarrage. Le meter : `/usr/bin/log show --last 30s | grep -cE 'PauseIO|ResumeIO'` (chemin absolu obligatoire, une fonction zsh masque `log`).

**⚠️ `b0ce8db` est COMMITÉ MAIS PAS POUSSÉ, volontairement.** Il touche le mute système, et sa garantie centrale — l'app ne démute jamais un mute que tu as fait toi-même — n'est pas vérifiable sans matériel. Les deux tests qui décident sont dans `TODO.md` § « What W0-2/W0-3 changed ».

**Ce qui a été livré (2026-07-28) — W0-9 et W0-4:**

**W0-9 — Vérification de disponibilité CLI avant l'enregistrement** (8 tests) : L'app te prévient AVANT de commencer l'enregistrement que le CLI ownscribe est absent, donc tu ne record plus une réunion entière puis apprends que rien ne peut la transcrire. Une bannière apparaît quand le CLI n'est pas dispo : *« Audio will be recorded but not transcribed — the ownscribe CLI is missing. Restore it, then run ./rec.sh redo <dir> to transcribe this meeting from its retained audio. »* La vérif tourne avant le start et une fois à l'ouverture de fenêtre. L'enregistrement est **autorisé** (pas désactivé) car la réunion est irremplaçable — l'audio survit pour un `redo` ultérieur. La vérif est pas chère (lookup env + un `isExecutableFile`, pas de walk PATH) et respecte le seam `pipelineRunnerFactory` injecté. Précédence bannière : `.failed` → avertissement mute → avertissement CLI → nil, donc un vrai échec ou un état mute-non-confirmé passe toujours en premier. Les tests épinglent la précédence et prouvent que la factory est appelée.

**W0-4 — Les compteurs sidebar fonctionnent maintenant** (implémenté par `builder-counts` en parallèle) : Les compteurs des filtres action et anchor étaient toujours à zéro car aucun writer n'existait — ils sont maintenant calculés à chaque refresh sidebar (0,44 ms, pas de cache nécessaire). Les compteurs sont `Int?` plutôt que `Int`, car sur les six réunions sur disque **une seule** a un `anchors.json`, et son objet `anchors` est `{}` — donc **zéro** a des ancres exploitables (mesuré le 2026-07-29). Render un compteur absent comme `0` clamerait « toutes les affirmations ont une preuve » pour des réunions jamais vérifiées, ce qui est l'échec du signal anti-hallucination W0-1. Absence → nil → rendu en texte grisé ou état UI distinct. Le piège qui se généralise : quand un compteur a une source-fichier qui peut ne pas exister (un `anchors.json` ajouté tardivement, une vérif différée), le typer `Int?` pour que l'absence ne se fasse pas passer pour zéro. Scope comme pas cher, donc pas de couche cache ajoutée.

Les deux défauts avaient la même forme : des valeurs câblées jusqu'à des consommateurs jamais appelés. Ni l'un ni l'autre n'était détectable par une suite verte.

**Un seul bug ouvert, trouvé le 2026-07-28** en traçant les valeurs jusqu'à leur CONSOMMATEUR : rien en Swift ne lit `envelope.json`, donc la timeline ne peut pas être dessinée (W0-5). La collision d'audio dans la même minute est corrigée (`d626e72`), et le blocage de l'app + la fuite du tap ont été **réfutés** sur le code livré : la garde d'identité de run de `b0ce8db` les avait fermés par effet de bord.

**Leçon la plus coûteuse de la journée** (six tentatives sur un seul correctif) : quand plusieurs consommateurs lisent une même chaîne, le moins exigeant passe et c'est le plus exigeant qui décide. `MeetingSummary` dérive deux valeurs du nom de dossier — la date (`parts[1]` doit valoir exactement `HHmm`) et le titre (`parts[2]` = le slug). **Tous les noms candidats parsaient la date ; un seul préservait le titre**, donc chaque test aller-retour bâti sur la date passait sur toutes les mauvaises réponses. Avant de changer un format : énumérer ses consommateurs (`grep -rn lastPathComponent`), asserter sur la sortie de *chacun*, et sonder toute regex en cinq lignes — « ça parse » est nécessaire, jamais suffisant.

**Piège de diagnostic à connaître** (un handoff d'une autre session s'y est fait prendre le 28/07) : cinq SIGTRAP `xctest` ont été attribués à `EnrolledSpeakerStore.names(in:)`, avec un correctif recommandé sur du code qui n'a **aucun** défaut — la fonction n'a jamais contenu d'`assertionFailure` de toute son histoire. `_assertionFailure` est le symbole de trap générique de Swift ; la frame au-dessus était `Array._checkSubscript`, donc un index hors limites. Et les cinq crashs tournaient depuis `/private/tmp/*/ownscribe-audioPackageTests` — des copies isolées d'agents de revue, pas le dépôt, dont la suite était verte pendant tout ce temps. Vérifier le chemin du bundle qui crashe avant de toucher la production.

**⚠️ Une seule chose attend l'utilisateur, et ce n'est plus « la voir ».** La fenêtre **a** été vue, deux fois le 28/07, et rejetée les deux fois (voir plus haut). Ce qui manque est une lecture *précise* : « pas bon du tout » porte sur l'ensemble, personne n'a nommé une partie. Donc la question est « ouvre `⌘0` et dis laquelle des huit vérifications de `APP_TEST.md` § Design pass échoue, et comment » — aucun audit ne peut la fermer, et deviner l'espacement encore moins. Le bundle installé est plus ancien que ces commits : relancer `bash swift/build-app.sh` d'abord (jamais depuis un agent : il `rm -rf` le bundle et ses autorisations TCC).

Le volet Réglages ajouté le 29/07 (micro + délai de silence) est dans le même cas : les tests prouvent que l'écriture du fichier de config est correcte, ils ne disent **rien** de son apparence. Personne ne l'a regardé.

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
