# LexiFR — notes de reprise pour les agents

## Produit et design

- App iPhone native SwiftUI, iOS 17+, portrait en priorité, iPhone 13 Pro.
- Design éditorial minimal : couleurs système, mot en titre serif, espace plutôt
  que cartes, SF Symbols, Dynamic Type, VoiceOver et modes clair/sombre.
- Pas de backend, compte, analytics, tracking ou téléchargement automatique.
- Google Images est uniquement une URL ouverte sur action explicite.

## Architecture

- `project.yml` est la source de vérité XcodeGen.
- `DictionaryRepository` est un actor et ouvre la ressource SQLite en lecture
  seule directement dans le bundle. Ne jamais copier la DB dans Application
  Support : cela doublerait plusieurs Go sur l’iPhone.
- `UserStore` est un actor SQLite distinct en WAL dans Application Support.
- Les favoris/collections stockent `entries.id`, jamais le rowid. Les clés
  entières `entry_rowid` de la base lexicale sont strictement internes.
- `WordImageStore` écrit des JPEG redimensionnés et miniatures hors de SQLite.

## Dictionnaire

- Dump local actuel : `Non confirmé 582917.crdownload`, JSONL UTF-8 brut,
  3 173 632 687 octets, 2 108 619 lignes valides.
- Base complète générée : `Database/french.sqlite` (ignorée par Git).
- Fixture bundle/test : `LexiFR/Resources/french.sample.sqlite`.
- Commande complète :

  ```powershell
  & 'C:\Users\LENOVO\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' Tools\build_dictionary.py --input '.\Non confirmé 582917.crdownload' --output '.\Database\french.sqlite' --force
  ```

- Le B-tree normalisé est la stratégie production. FTS5 est opt-in avec
  `--fts`; ne pas l’activer dans la base embarquée sans revalider la taille.
- L’identifiant stable est `kaikki:<sense-id>:<discriminant-12-hex>`, avec un
  SHA-256 lexical de secours si Kaikki ne fournit pas d’id.
- La normalisation Python et Swift doit rester alignée : NFKC/folding,
  case/accents ignorés, œ→oe, æ→ae, apostrophes unifiées, espaces réduits.

## Tests et commandes

```bash
python3 -m unittest discover -s Tools/tests -v
python3 Tools/verify_dictionary.py --database Database/french.sqlite --minimum-entries 100000
python3 Tools/benchmark_dictionary.py --database Database/french.sqlite --iterations 100
xcodegen generate
xcodebuild test -project LexiFR.xcodeproj -scheme LexiFR -destination 'platform=iOS Simulator,name=iPhone 16 Pro' CODE_SIGNING_ALLOWED=NO
```

L’environnement Windows courant ne possède pas Xcode/Swift. Ne prétendre à un
build iOS local réussi qu’après exécution sur Mac/Codemagic.

## Packaging et CI

- Le dump brut et les grosses SQLite sont ignorés par Git.
- Le build Codemagic ne reconstruit jamais le corpus. Il restaure
  `Database/french.sqlite` du cache, ou utilise explicitement
  `LEXIFR_DICTIONARY_URL` pour amorcer ce cache.
- Conserver `french.sample.sqlite` pour que les tests restent reproductibles.
- Variables CI : `LEXIFR_BUNDLE_ID`, `APPLE_TEAM_ID`, URL DB optionnelle et
  secrets de signature dans Codemagic, jamais dans le repository.

## Licence

- Attribution Wiktionnaire + Kaikki/Wiktextract.
- CC BY-SA 4.0 ou GFDL selon le contenu ; voir `ATTRIBUTIONS.md`.
