# Workflows charges par defaut

Deposez ici votre fichier `.json` exporte depuis ComfyUI
(menu ComfyUI > Fichier > Exporter).

Tout ce qui se trouve dans ce dossier est copie dans
`ComfyUI/user/default/workflows/` au moment du build, et apparait donc
directement dans l interface du pod.

Ce fichier README sert aussi a ce que le dossier existe dans Git :
sans lui, Git ne versionne pas un dossier vide et la ligne
`COPY workflows/ ...` du Dockerfile echouerait.
