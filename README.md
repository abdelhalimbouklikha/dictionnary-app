# LexiFR

LexiFR est un dictionnaire français → français natif pour iPhone. La recherche,
les définitions, les favoris, les collections et les images personnelles
fonctionnent hors ligne. Le seul accès externe déclenché par l’app est le bouton
explicite « Voir sur Google Images ».

## Fonctionnalités

- recherche exacte, par préfixe, sans accents, insensible à la casse et aux
  variantes d’apostrophes ;
- recherche des flexions sans parcourir le dictionnaire en mémoire ;
- définitions, prononciations IPA, exemples, synonymes, antonymes, dérivés,
  relations, formes et étymologie lorsqu’ils existent ;
- favoris et collections multiples, avec quatre tris basés sur de vrais
  timestamps ;
- image personnelle via PhotosPicker, original redimensionné et miniature JPEG ;
- historique récent local borné à 30 mots et effaçable ;
- SwiftUI, NavigationStack, TabView, Dynamic Type, VoiceOver, mode clair/sombre ;
- partage d’une définition courte et ouverture encodée de Google Images.

## Architecture

L’app ne possède ni backend, ni compte, ni analytics. Elle utilise deux stockages :

1. `french.sqlite`, immutable et ouverte directement depuis le bundle en mode
   `query_only`, contient le dictionnaire complet ;
2. `Application Support/LexiFR/user.sqlite`, en WAL, contient uniquement les
   favoris, collections, associations, préférences, historique et chemins
   d’images.

Les favoris utilisent un identifiant logique stable dérivé de l’identifiant de
sens Kaikki et d’un discriminant lexical. Les rowids entiers ne servent qu’aux
jointures internes compactes de la base de dictionnaire. Une reconstruction de
la base ne réindexe donc pas arbitrairement les données personnelles.

La recherche interactive utilise un index B-tree sur `normalized_word` et
`normalized_form`, une borne de préfixe Unicode, un debounce de 130 ms et
l’annulation des tâches obsolètes. FTS5 est disponible avec `--fts`, mais n’est
pas activé en production : sur le corpus réel, le B-tree est plus compact et les
requêtes mesurées étaient déjà inférieures au milliseconde.

## Prérequis

- macOS avec Xcode 16 ou plus récent pour compiler l’app ;
- iOS 17 ou plus récent (iPhone uniquement, validé dans la configuration pour
  l’iPhone 13 Pro) ;
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.41+ ;
- Python 3.11+ pour préparer la base.

Le workspace actuel a été préparé sous Windows : Python 3.12 est disponible via
le runtime Codex, mais Xcode/Swift ne sont pas installés sur cette machine. Les
tests iOS doivent donc être exécutés sur un Mac ou par Codemagic.

## Dictionnaire Kaikki

Le dump détecté est `Non confirmé 582917.crdownload`. Malgré ce suffixe Chrome,
il s’agit d’un JSONL UTF-8 non compressé complet : 3 173 632 687 octets et
2 108 619 lignes JSON valides. Le parseur se fie aux octets magiques et accepte
aussi gzip, bzip2 et xz.

Le schéma observé réellement contient notamment `word`, `lang_code`, `pos`,
`pos_title`, `sounds`, `senses`, `examples`, `forms`, `synonyms`, `antonyms`,
`derived`, `related`, `etymology_texts` et un `id` stable par sens.

## Générer la SQLite

Depuis la racine du repository :

```powershell
& 'C:\Users\LENOVO\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' `
  Tools\build_dictionary.py `
  --input '.\Non confirmé 582917.crdownload' `
  --output '.\Database\french.sqlite' `
  --force
```

Commande portable sur macOS/Linux :

```bash
python3 Tools/build_dictionary.py \
  --input "/chemin/vers/kaikki.org-dictionary-French.jsonl" \
  --output "Database/french.sqlite" \
  --force
```

Prototype limité :

```bash
python3 Tools/build_dictionary.py --input dump.jsonl \
  --output Database/french.sample.sqlite --sample 25000 --force
```

Validation et benchmark :

```bash
python3 Tools/verify_dictionary.py --database Database/french.sqlite --minimum-entries 100000
python3 Tools/benchmark_dictionary.py --database Database/french.sqlite --iterations 100
python3 -m unittest discover -s Tools/tests -v
```

Le script traite le fichier en streaming, commit par batches, ignore et compte
les lignes invalides, crée les index après l’import, exécute `ANALYZE` et
`PRAGMA optimize`, puis écrit un rapport `*.stats.json`.

## Taille et statistiques

Les statistiques mesurées sont conservées dans
`Database/french.sqlite.stats.json`. La base complète optimisée contient :

- source JSONL : 3 173 632 687 octets ;
- lignes valides : 2 108 619 ;
- entrées lexicales : 2 108 616 ;
- mots distincts normalisés : 1 835 361 ;
- sens : 2 652 800 ;
- exemples : 715 949 ;
- prononciations : 1 862 633 ;
- formes : 5 754 449 ;
- relations : 866 637.

La SQLite finale mesure **1 862 275 072 octets (1,73 Gio)**. Sa version gzip de
transport mesure **622 393 242 octets (593,6 Mio)** ; l’app utilise toujours la
SQLite brute afin de l’ouvrir directement en lecture seule.
La première version, avec clés texte répétées et FTS5, mesurait
3 759 955 968 octets ; elle a été remplacée par le schéma compact actuel afin de
respecter une marge réaliste pour le packaging iOS.

Sur la base complète et 100 itérations par requête, les médianes mesurées vont de
0,19 ms (`lire`) à 6,34 ms (`être`, qui possède énormément de flexions), avec un
p95 maximal de 6,93 ms. Le détail est dans `BUILD_REPORT.md`.

## Ouvrir dans Xcode

Le projet est défini de façon reproductible dans `project.yml` :

```bash
brew install xcodegen
export LEXIFR_BUNDLE_ID="com.votredomaine.LexiFR"
export APPLE_TEAM_ID="VOTRE_TEAM_ID"
xcodegen generate
open LexiFR.xcodeproj
```

XcodeGen inclut directement `Database/french.sqlite` dans le bundle : aucune
copie source supplémentaire de plusieurs Go n’est créée. Sans cette base, l’app
utilise volontairement `french.sample.sqlite` pour le développement et les
tests. Une archive de distribution doit toujours inclure la base complète.

## Lancer sur simulateur

```bash
xcodebuild test \
  -project LexiFR.xcodeproj \
  -scheme LexiFR \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO
```

Un simulateur iPhone 13 Pro peut être sélectionné dans Xcode s’il est installé.

## Lancer sur iPhone

Dans Xcode, sélectionnez le target LexiFR, votre Team, un Bundle ID unique, puis
l’iPhone 13 Pro comme destination et utilisez **Run**. Ce flux Development est
le plus direct pour votre appareil personnel ; l’app devra être resignée selon
la durée prévue par votre type de compte Apple.

## Codemagic

`codemagic.yaml` sépare trois workflows : tests avec la petite fixture, IPA Ad
Hoc, et archive TestFlight/App Store. Les builds Swift ne reconstruisent jamais
le dump de plusieurs Go. La SQLite finale est restaurée depuis le cache
Codemagic ; seulement si le cache est vide, une URL explicitement configurée
peut la fournir.

Variables à configurer dans Codemagic :

- `LEXIFR_BUNDLE_ID` : Bundle ID enregistré dans Apple Developer ;
- `APPLE_TEAM_ID` : identifiant de l’équipe Apple ;
- `LEXIFR_DICTIONARY_URL` : URL privée/éphémère de la SQLite préconstruite pour
  amorcer le cache (SQLite brute ou `.gz`, jamais le dump JSONL) ;
- certificat Apple Distribution et provisioning profile Ad Hoc, ou intégration
  App Store Connect pour TestFlight/App Store.
- pour la publication API : `APP_STORE_CONNECT_PRIVATE_KEY`,
  `APP_STORE_CONNECT_KEY_IDENTIFIER` et `APP_STORE_CONNECT_ISSUER_ID`.

Placez `LEXIFR_BUNDLE_ID`, `APPLE_TEAM_ID` et, si nécessaire,
`LEXIFR_DICTIONARY_URL` dans un groupe nommé `lexifr_config`. Placez les trois
secrets App Store Connect dans `app_store_credentials`. Ces deux groupes sont
déjà référencés par les workflows concernés.

Ne placez jamais certificat, profil, mot de passe ou clé API dans le YAML.

## Signature

- **Development** : Xcode + appareil enregistré, idéal pendant le développement ;
- **Ad Hoc** : certificat Distribution + profil contenant l’UDID de l’iPhone,
  produit une IPA installable directement ; utilisez `ios-ad-hoc` ;
- **TestFlight/App Store** : profil App Store et intégration App Store Connect ;
  utilisez `ios-app-store`.

Pour une installation personnelle via Codemagic, le workflow Ad Hoc est le plus
approprié une fois l’UDID de l’iPhone 13 Pro inclus dans le profil.

## Mettre à jour le dictionnaire

1. conserver `user.sqlite` et le dossier `WordImages` ;
2. télécharger un nouveau dump Kaikki hors du pipeline Swift ;
3. reconstruire `Database/french.sqlite` ;
4. exécuter les tests et le benchmark ;
5. vérifier les statistiques et la taille ;
6. remplacer uniquement la ressource immutable de la prochaine version.

Le stockage utilisateur n’est jamais inclus dans cette opération.

## Sources et licences

Voir [ATTRIBUTIONS.md](ATTRIBUTIONS.md). Les données proviennent du Wiktionnaire
via Kaikki/Wiktextract et sont attribuées sous CC BY-SA 4.0 ou, suivant le
contenu, GFDL. Aucune donnée du Robert ou de Larousse n’est incluse.

## Structure du projet

```text
LexiFR/                 application SwiftUI
  App/                  bootstrap et TabView
  Database/             normalisation et SQLite C API
  Repositories/         dictionnaire immutable et données utilisateur
  Services/             images et URL Google Images
  Features/             recherche, fiche, favoris, collections, réglages
  Resources/            assets et base miniature
LexiFRTests/            tests unitaires iOS
LexiFRUITests/          smoke tests UI
Tests/Fixtures/         fixture JSONL indépendante du dump complet
Tools/                  import, validation et benchmark
Database/               sortie locale de la base complète (ignorée par Git)
```

## Troubleshooting

- **Ressource absente** : générez/copiez `LexiFR/Resources/french.sqlite`, ou
  gardez `french.sample.sqlite` pour un build de test.
- **Base corrompue** : lancez `Tools/verify_dictionary.py`; l’app affiche une
  erreur de lancement au lieu de crasher.
- **XcodeGen réclame une variable** : exportez `LEXIFR_BUNDLE_ID` et
  `APPLE_TEAM_ID` avant `xcodegen generate`.
- **Archive trop volumineuse** : vérifiez que la base compacte sans `--fts` est
  utilisée et qu’aucun dump JSONL n’est membre du target.
- **Signature Codemagic** : le Bundle ID du profil doit être strictement égal à
  `LEXIFR_BUNDLE_ID` et le profil Ad Hoc doit contenir l’UDID de l’appareil.
