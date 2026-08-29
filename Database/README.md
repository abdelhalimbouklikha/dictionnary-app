# Base complète locale

Placez ici la sortie `french.sqlite` de `Tools/build_dictionary.py`.

Le fichier est volontairement ignoré par Git. XcodeGen inclut directement cette
ressource dans le target lorsqu’elle est présente, sans seconde copie dans les
sources. Codemagic la restaure au même emplacement depuis son cache et ne
reconstruit jamais le dump pendant un build Swift.
