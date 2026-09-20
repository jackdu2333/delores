# Petdex companion asset evidence

This document records the provenance evidence for the seven Petdex assets used to build Delores
companion atlases. It is an audit snapshot, not a substitute for the licence text of any individual
asset.

## Evidence snapshot

- Checked: 2026-09-20 (Asia/Shanghai)
- Source-of-truth list: [`Scripts/gen-companion-petdex.py`](../../Scripts/gen-companion-petdex.py)
- Petdex manifest: <https://petdex.dev/api/manifest>
- Manifest `generatedAt`: `2026-09-19T19:50:04.731Z`
- Matching rule: each row below was matched by the exact `spritesheetUrl` in the manifest.

Petdex's [licence note](https://github.com/crafter-station/petdex#license) separates its source-code
licence from its pet assets: the source code is MIT, while pet assets are owned by their submitters
under the licence they declare. Delores does not apply Petdex's source-code licence to these assets.

The captured public manifest and each matching `petjson.json` expose identity, provenance and
submitter metadata, but no per-asset licence identifier. The absence is recorded here instead of
being replaced with an inferred MIT, Apache or Creative Commons licence.

## Seven shipped assets

| Delores atlas | Manifest slug | Display name | `submittedBy` in manifest | Petdex origin entry | Source asset | Pet JSON |
| --- | --- | --- | --- | --- | --- | --- |
| `CompanionAtlas-nezuko.generated.png` | `nezukocoder` | NezukoCoder | Miro H. | <https://petdex.dev/pets/nezukocoder> | <https://assets.petdex.dev/pets/nezukocoder-7d766f7c2597/sprite.webp> | <https://assets.petdex.dev/pets/nezukocoder-7d766f7c2597/petjson.json> |
| `CompanionAtlas-ddoZvzo.generated.png` | `ddo-zvzo-2` | ddo-zvzo | 준회 Junhoe Kim 김. | <https://petdex.dev/pets/ddo-zvzo-2> | <https://assets.petdex.dev/pets/ddo-zvzo-49f5c2067af6/sprite.webp> | <https://assets.petdex.dev/pets/ddo-zvzo-49f5c2067af6/petjson.json> |
| `CompanionAtlas-whaledou.generated.png` | `whaledou` | whaledou | isdou | <https://petdex.dev/pets/whaledou> | <https://assets.petdex.dev/pets/whaledou-c4cb6b24fb56/sprite.webp> | <https://assets.petdex.dev/pets/whaledou-c4cb6b24fb56/petjson.json> |
| `CompanionAtlas-xiaoHei.generated.png` | `nightleaf` | Xiao Hei | 国东 闵. | <https://petdex.dev/pets/nightleaf> | <https://assets.petdex.dev/pets/nightleaf-3ffbd69b2946/sprite.webp> | <https://assets.petdex.dev/pets/nightleaf-3ffbd69b2946/petjson.json> |
| `CompanionAtlas-gugugaga.generated.png` | `gugugaga-2` | 咕咕嘎嘎 | c u. | <https://petdex.dev/pets/gugugaga-2> | <https://assets.petdex.dev/pets/gugugaga-cedf2dac1434/sprite.webp> | <https://assets.petdex.dev/pets/gugugaga-cedf2dac1434/petjson.json> |
| `CompanionAtlas-lillia.generated.png` | `snow-plum-lillia` | Snow Plum Lillia Codex Pet | du B. | <https://petdex.dev/pets/snow-plum-lillia> | <https://assets.petdex.dev/pets/snow-plum-lillia-2a5fc9e46017/sprite.webp> | <https://assets.petdex.dev/pets/snow-plum-lillia-2a5fc9e46017/petjson.json> |
| `CompanionAtlas-dog.generated.png` | `aka-shiba` | July | hopeloop | <https://petdex.dev/pets/aka-shiba> | <https://assets.petdex.dev/pets/aka-shiba-5758e3fbe12c/sprite.webp> | <https://assets.petdex.dev/pets/aka-shiba-5758e3fbe12c/petjson.json> |

`submittedBy` is copied verbatim from the manifest snapshot. Petdex may show a localized display
name or a creator handle on an individual entry page; the linked origin entry remains the current
source for attribution review.

## Licence and attribution boundary

The project maintainer has confirmed that all seven source assets are open-source. Their source
attribution and applicable licence evidence must be preserved individually. The public evidence
above independently establishes the seven asset identities, origin entries, source URLs and
manifest submitters. It does not establish a specific licence identifier, version or exact
attribution wording for any row.

Before a public release, retain the submitter's declared licence or the original upstream licence
record for each row. If an origin entry does not expose that declaration, do not infer one from the
Petdex repository licence or from another asset; keep the row marked as requiring a preserved
submitter/upstream licence record.
