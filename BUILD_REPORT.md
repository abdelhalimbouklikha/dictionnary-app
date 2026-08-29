# Rapport de build LexiFR

## Build

**NON EXÉCUTÉ LOCALEMENT** — le workspace courant est Windows et ne possède ni
Xcode, ni Swift, ni `xcodebuild`. Le projet reproductible XcodeGen, les trois
targets, le scheme partagé et le workflow Codemagic ont été créés. Le premier
build iOS doit être lancé sur macOS/Codemagic.

## Tests

- pipeline Python : **9 réussis, 0 échoué** ;
- `py_compile` des quatre modules Python : réussi ;
- intégrité SQLite complète (`PRAGMA quick_check`) : **ok** ;
- tests XCTest écrits : 6 unitaires, non exécutés faute de Xcode ;
- smoke tests XCUITest écrits : 2, non exécutés faute de simulateur.

## Dump détecté

- nom exact : `Non confirmé 582917.crdownload` ;
- format réel : JSONL UTF-8 non compressé ;
- taille exacte : **3 173 632 687 octets** ;
- lignes logiques : **2 108 619** ;
- échantillon inspecté : 40/40 lignes valides, langue `fr` ;
- dernière ligne : JSON complet valide, même sans saut de ligne terminal.

## Import

- lignes traitées : **2 108 619** ;
- JSON valides : **2 108 619** ;
- erreurs JSON/UTF-8 : **0** ;
- entrées conservées : **2 108 616** ;
- lignes ignorées : 3 (dont 2 identifiants exactement dupliqués) ;
- mots distincts normalisés : **1 835 361** ;
- sens : **2 652 800** ;
- exemples : **715 949** ;
- prononciations : **1 862 633** ;
- formes : **5 754 449** ;
- relations : **866 637** ;
- durée du dernier import : **233,203 s**.

## SQLite

- chemin : `C:\Users\LENOVO\Desktop\application dictionnaire\Database\french.sqlite` ;
- taille : **1 862 275 072 octets (1,73 Gio)** ;
- gzip : `Database/french.sqlite.gz`, **622 393 242 octets (593,6 Mio)** ;
- SHA-256 SQLite/données décompressées :
  `66885bec73701338c83c8f705c9eee5a59fffb8977bb6c1b82f7bf5873199619` (identiques) ;
- schéma : version 1 ;
- intégrité : `ok` ;
- packaging : ressource unique ouverte directement depuis le bundle, sans copie
  dans Application Support.

## Recherche

Architecture : normalisation Unicode séparée de l’affichage, index B-tree sur
les mots et formes, requêtes par intervalle de préfixe, limite 40 dans l’app,
actor Swift, debounce 130 ms et annulation de la tâche précédente.

Résultats base complète, 100 itérations après warm-up :

| Requête | Médiane | p95 | Maximum |
|---|---:|---:|---:|
| accueil | 0,229 ms | 0,277 ms | 0,373 ms |
| lire | 0,194 ms | 0,232 ms | 0,253 ms |
| ecole | 0,360 ms | 0,588 ms | 1,093 ms |
| épan | 0,722 ms | 1,082 ms | 1,172 ms |
| coeur | 0,368 ms | 0,566 ms | 0,700 ms |
| être | 6,335 ms | 6,931 ms | 7,229 ms |

FTS5 a aussi été mesuré sur 25 000 entrées : environ 0,06–0,07 ms contre
0,12–0,18 ms pour le B-tree, mais +5,4 % de taille et sans la sémantique des
flexions. Il reste opt-in (`--fts`) et n’est pas inclus dans la base production.

## Application

Écrans implémentés : Recherche, fiche mot, Favoris, Collections, détail d’une
collection et Réglages/Sources et licences. Sont également implémentés : image
personnelle + miniature, remplacement/suppression, relations navigables,
partage, Google Images, historique local, états vides, tri et haptics.

## Codemagic

Fichier créé : `codemagic.yaml`.

À fournir : groupe `lexifr_config` (`LEXIFR_BUNDLE_ID`, `APPLE_TEAM_ID`,
`LEXIFR_DICTIONARY_URL` pour amorcer le cache), certificat/profil Ad Hoc ou App
Store, et groupe `app_store_credentials` (`APP_STORE_CONNECT_PRIVATE_KEY`,
`APP_STORE_CONNECT_KEY_IDENTIFIER`, `APP_STORE_CONNECT_ISSUER_ID`).

## Installation iPhone

Prochaine action : pousser le projet dans un dépôt, créer les deux groupes de
variables Codemagic, enregistrer l’UDID de l’iPhone 13 Pro dans un profil Ad Hoc,
puis lancer le workflow `ios-ad-hoc`. Pour le développement direct, ouvrir le
projet généré sur Mac, choisir votre Team et exécuter sur l’iPhone connecté.

## Limites restantes

- compilation Swift/Xcode et simulateur non exécutables sur cette machine
  Windows ;
- signature, Bundle ID final, certificat et profils dépendent de votre compte
  Apple ;
- la grosse SQLite et son gzip sont volontairement ignorés par Git : le premier
  workflow release doit amorcer le cache avec l’URL privée configurée.
