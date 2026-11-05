<p align="center">
  <img src="../doni-icon.png" width="128" alt="Icône de l'app Doni : un avion en papier blanc sur des notes estompées, en rouge">
</p>

# Doni

[English](../../README.md) · [Tiếng Việt](README.vi.md) · [中文](README.zh.md) · [Español](README.es.md) ·
**Français** · [Русский](README.ru.md) · [العربية](README.ar.md)

<p align="center">
  <a href="https://github.com/williamcachamwri/Doni/releases/latest"><img src="https://img.shields.io/github/v/release/williamcachamwri/Doni?label=release&color=blue" alt="Dernière version"></a>
  <img src="https://img.shields.io/badge/iOS-26.0%2B-blue" alt="iOS 26.0 ou version ultérieure">
  <a href="https://developer.apple.com/swift/"><img src="https://img.shields.io/badge/Swift-6-F05138" alt="Swift 6"></a>
  <img src="https://img.shields.io/badge/arch-arm64-lightgrey" alt="uniquement arm64">
</p>

Un lecteur de musique pour iPhone qui joue les titres déjà présents dans votre Telegram : les chaînes
abonnées et Saved Messages comme bibliothèque personnelle. Pas de serveur, pas d'inscription, aucune
donnée envoyée.

<table>
  <tr>
    <td><img src="../screenshots/home.jpg" width="220"></td>
    <td><img src="../screenshots/now-playing.jpg" width="220"></td>
    <td><img src="../screenshots/lock-screen.jpg" width="220"></td>
    <td><img src="../screenshots/playlist.jpg" width="220"></td>
  </tr>
</table>

## Ce qu'il fait

- **Démarrage immédiat, téléchargement pendant la lecture.** Le fichier est demandé par plages d'octets
  autour de la position : aller à 3:40 demande la partie autour de 3:40, pas le fichier entier.
- **Il garde ce qu'il a pris.** Les morceaux restent sur le téléphone même si l'app est tuée ; un titre
  déjà écouté en entier fonctionne hors réseau.
- **Cloud Music, c'est Saved Messages.** Téléverser un fichier l'envoie dans votre propre conversation
  puis supprime la copie locale ; supprimé dans Telegram, il disparaît aussi d'ici.
- **Paroles horodatées** via lrclib, NetEase, AMLL et QQ Music. Le verset en cours remplace le titre sur
  l'écran de verrouillage et dans la Dynamic Island.
- **Pochettes** prises dans les étiquettes du fichier ou la vignette de Telegram ; si Telegram ne l'a pas
  encore générée, la question est posée de nouveau quelques fois.
- **Cache plafonné.** Le quota vous appartient (2 GiB par défaut), les titres le moins écoutés partent en
  premier, jamais celui qui joue.
- Six langues dans l'interface ; les chaînes du code sont en vietnamien.

## Pourquoi Telegram

Parce que la bibliothèque existe déjà. Chaque titre est un message portant un fichier, chaque fichier a un
`file_unique_id` qui désigne les mêmes octets dans n'importe quelle base. « Ai-je déjà ce titre ? » et
« où m'étais-je arrêté ? » reçoivent une réponse du protocole plutôt que d'un serveur que je devrais
financer et qui lirait vos données. TDLib s'occupe du réseau : connexion, reprises, téléchargements,
cache de fichiers, redirections CDN.

## Le streaming, concrètement

- `downloadFile` prend un décalage et une limite, mais la limite n'arrête rien : TDLib continue jusqu'à
  annulation, donc l'app ferme chaque fenêtre elle-même.
- `getFileDownloadedPrefixSize` indique combien d'octets sont prêts à *n'importe quel* décalage. C'est le
  masque de préparation, pas un drapeau « fini ou non », et c'est ce qui rend utile un fichier incomplet.
- Les parts font 64 KiB. La fenêtre avance de quelques mégaoctets et se déplace à mi-consommation.
- AVFoundation demande ses octets par `AVAssetResourceLoaderDelegate`, ouvre avec une sonde de 2 octets et
  refuse une réponse plus longue que ce qu'il a demandé.
- Hors fenêtre, les octets sont du bruit. Rien n'entre dans le décodeur sans validation de TDLib, donc une
  coupure réseau arrête la musique au lieu d'en faire sortir de la parasites.

## Compiler

Il faut iOS 26, Xcode 26, [XcodeGen](https://github.com/yonaskolb/XcodeGen), CMake, Python 3 et un
`api_id`/`api_hash` de [my.telegram.org](https://my.telegram.org).

```sh
make vendor       # compile TDLib et OpenSSL (une vingtaine de minutes)
make project      # génère Doni.xcodeproj
cp Config/Tdlib.example.xcconfig Config/Tdlib.xcconfig   # vos valeurs, fichier non publié
make build        # un avertissement est une erreur
make device && make install
```

## Publier

Une version, deux numéros, tous deux dans `project.yml`, à changer ensemble. `MARKETING_VERSION` est
celle qu'affiche « À propos » et que doit porter l'étiquette ; `CURRENT_PROJECT_VERSION` est le numéro de
compilation qui encode la même version : `90 | majeur | mineur | correctif`, donc `9010000` vaut 1.0.0.
Les notes de version s'écrivent une fois dans `RELEASE_NOTES.md`, en deux langues et en même nombre de
lignes.

## Limites

- Signature en équipe gratuite : 3 appareils, certificat mort au bout de 7 jours.
- L'IPA publié n'est pas signé ; il faut le resigner avec votre équipe. `make release` le compile ici, étiquette la version, pousse et joint l'IPA ; le workflow reste en déclenchement manuel depuis Actions, pour prouver que la compile marche sur un checkout propre.
- Pas de CarPlay pour l'instant : l'autorisation `carplay-audio` exige un compte payant.
- Les paroles viennent de sources publiques ; un titre que personne n'a retranscrit n'a pas de paroles, et
  l'app le dit au lieu d'afficher une page vide.
- La vérification de mise à jour prévient et ouvre la page de publication ; elle n'installe rien.

## Licence et crédits

GPL-3.0 ([LICENSE](../../LICENSE)) : l'écran des paroles et plusieurs vues viennent de
[MeloX](https://github.com/youshen2/MeloX), qui est GPLv3. **TDLib** (BSL 1.0), **OpenSSL** (Apache-2.0),
**SQLite** pour la bibliothèque et les listes, **Telegram-iOS** (GPL-2.0) uniquement pour mesurer espacements
et couleurs — aucune ligne de son code ici.

Doni n'est affilié ni autorisé par Telegram ou un quelconque service de musique. Il ouvre des fichiers déjà
dans votre compte.

Contact : Telegram [@w1lliamcachamwri](https://t.me/w1lliamcachamwri) ·
[github.com/williamcachamwri/Doni](https://github.com/williamcachamwri/Doni)

