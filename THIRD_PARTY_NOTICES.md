# Third-party notices

Godot 4.7.2 is MIT licensed. Export packages include the Godot license and copyright notice.

Node.js 24.21.0 runtime is distributed under its LICENSE (included with desktop packages).

Noto Sans SC font is licensed under SIL Open Font License 1.1; see assets/fonts/OFL.txt.

The JavaScript game rules are source snapshots of the same author’s three-kingdoms project, recorded in vendor/legacy/provenance.json and vendor/shared/provenance.json. The shared-world service and transaction modules are preserved unchanged; their runtime adapter reuses the legacy runtime. No screenshots or proprietary source-game assets are copied.

Sound Manager 2.6.2 by Nathan Hoad is MIT licensed; pinned upstream commit `1c041582db806a0d0edad77111d1fb7a009346ef`. Source: https://github.com/nathanhoad/godot_sound_manager. License: docs/licenses/sound-manager-MIT.txt.

Dialogue Manager 4.1.0 by Nathan Hoad is MIT licensed; pinned upstream commit `8ffe461f2a69180a35b2f00f31b563bfe6231da8`. Source: https://github.com/nathanhoad/godot_dialogue_manager. License: docs/licenses/dialogue-manager-MIT.txt.

The paginated tab container from Maaack's Game Template is MIT licensed; pinned upstream commit `6849d6c352dafe8ed54b5fa4f4b9774adfca31c8`. Source: https://github.com/Maaack/Godot-Game-Template. Only this standalone component is imported, in addons/maaacks_menu; the rest of the template is not installed. License: docs/licenses/maaack-menu-MIT.txt.

The demonstration synthesized music and cues in src/presentation_audio.gd are original project code; they contain no downloaded recordings.

## node-postgres

Cloud room persistence uses node-postgres (`pg` 8.23.1), licensed under MIT. The license is included at [docs/licenses/node-postgres-MIT.txt](docs/licenses/node-postgres-MIT.txt). It is installed on the Node server; account passwords and database credentials are not included in exported clients.
