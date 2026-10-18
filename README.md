# EvaMeet · téléchargements

Installateurs publics signés d’EvaMeet, par Global Management Inc.

Le code de l’application est conservé dans un dépôt privé. Ce dépôt contient
uniquement les fichiers destinés à être distribués, leurs signatures, les
licences et les sources des composants libres correspondants.

L’application nécessite un compte Eva et un abonnement actif de votre organisation.
Les versions proposées aux utilisateurs sont accessibles depuis
[Télécharger EvaMeet](https://v2.eva-ia.ca/plateforme/evameet/telecharger).

## FFmpeg

Le programme FFmpeg est exécuté séparément pour préparer les fichiers audio et
filmer les séances. Notre compilation Windows reste sous LGPL 2.1 ou ultérieure,
sans composant GPL, non libre ou version 3, ni fonctions réseau. Pour la vidéo,
elle utilise les encodeurs déjà présents sur le poste : Media Foundation, livré
avec Windows, et NVENC ou AMF, livrés avec les pilotes NVIDIA et AMD. FFmpeg les
charge à l’exécution ; seuls leurs en-têtes, sous licence MIT, servent à la
compilation, et leurs avis accompagnent le binaire.
Les archives de chaque version contiennent les sources exactes, la recette de
compilation, les paramètres générés et les licences. Aucune source FFmpeg n’est modifiée.

Les archives de dépendances ne sont pas des installateurs EvaMeet.
