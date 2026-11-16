# App logos

One SVG per app in `apps.nix`, named after its id. The dashboard's app
catalog shows them; an app without one gets its initials instead.

Most come from [svgl](https://svgl.app) (light variants), fetched from
`static/library/` in its GitHub repo, pheralb/svgl. svgl has no
Flatpak, LibreOffice or Inkscape logo, so `flatpak.svg` is from
[Simple Icons](https://simpleicons.org) (filled in Flatpak's blue) and
`libreoffice.svg` and `inkscape.svg` are from the Papirus icon theme.
`go.svg` is recoloured to Go's blue.
`eas.svg` is svgl's Expo logo, `android-sdk.svg` its Android icon and
`copilot-cli.svg` its GitHub Copilot logo. svgl's AMP logo is a different
project, so `amp.svg` is Amp's own favicon, from ampcode.com.

The 3D printing apps aren't in svgl either. `bambu-studio.svg` (Bambu
Lab's mark), `openscad.svg` and `freecad.svg` are from Simple Icons, filled
in each brand's colour. `orca-slicer.svg` and `prusa-slicer.svg` are the
apps' own icons, from their GitHub repos (SoftFever/OrcaSlicer and
prusa3d/PrusaSlicer).

The logos are trademarks of their owners and are used only to name their
software.
