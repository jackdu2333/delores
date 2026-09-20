# Third-party notices

Tinycast and Delores code in this repository are distributed under the GNU Affero General Public
License v3 or later — see [LICENSE](LICENSE). It
also redistributes the third-party material recorded below, under the terms stated for each.

## Brand marks — `Tinycast/Assets.xcassets/AIBrand*.imageset`

Thirteen monochrome template SVGs, ~300 B–2 KB each, drawn beside a model's name in the model
picker and the chat header so a route is recognisable at a glance.

Every mark is the trademark of the company it identifies. Tinycast uses them only to name that
company's own models inside its own UI. No affiliation, sponsorship or endorsement is implied, and
none of these companies has reviewed or approved Tinycast.

### Simple Icons — twelve marks

`claude`, `deepseek`, `googlegemini`, `kimi`, `meta`, `minimax`, `mistralai`, `openai`,
`openrouter`, `perplexity`, `qwen` and `x`, from <https://github.com/simple-icons/simple-icons>.

The Simple Icons **project** is released under CC0 1.0 Universal. Its own disclaimer is explicit
that this does not extend to every mark the project carries: the icons depict third-party brands
whose trademarks stay with their owners, and the absence of licence data for a given icon does not
imply the icon is unlicensed. Anyone redistributing Tinycast, or reusing these files from it,
should read the disclaimer and satisfy themselves about the brands involved:
<https://github.com/simple-icons/simple-icons/blob/develop/DISCLAIMER.md>.

### Lobe Icons — one mark

`zai`, from <https://github.com/lobehub/lobe-icons>, which is MIT licensed. Its licence requires
this notice to travel with the work:

```
MIT License

Copyright (c) 2023 LobeHub

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Companion skins — Petdex source assets

Delores optionally includes companion skins built from seven open-source pet assets distributed
through [Petdex](https://petdex.dev/). The project reslices and scales selected source frames into
its own companion atlases. These skins are optional: users may choose among supported pets or turn
the Companion off, and using a pet created by this project is never required.

The project maintainer has confirmed that the seven source assets below are open-source. This list
records the direct source asset URLs for provenance. Before redistributing or modifying a source
asset, verify the applicable licence and attribution requirements in its corresponding Petdex origin
entry. This NOTICE does not infer or assign a single licence to all Petdex assets.

| Shipped atlas | Petdex asset | Source |
| --- | --- | --- |
| `CompanionAtlas-nezuko.generated.png` | `nezukocoder` | <https://assets.petdex.dev/pets/nezukocoder-7d766f7c2597/sprite.webp> |
| `CompanionAtlas-ddoZvzo.generated.png` | `ddo-zvzo` | <https://assets.petdex.dev/pets/ddo-zvzo-49f5c2067af6/sprite.webp> |
| `CompanionAtlas-whaledou.generated.png` | `whaledou` | <https://assets.petdex.dev/pets/whaledou-c4cb6b24fb56/sprite.webp> |
| `CompanionAtlas-xiaoHei.generated.png` | `nightleaf` | <https://assets.petdex.dev/pets/nightleaf-3ffbd69b2946/sprite.webp> |
| `CompanionAtlas-gugugaga.generated.png` | `gugugaga` | <https://assets.petdex.dev/pets/gugugaga-cedf2dac1434/sprite.webp> |
| `CompanionAtlas-lillia.generated.png` | `snow-plum-lillia` | <https://assets.petdex.dev/pets/snow-plum-lillia-2a5fc9e46017/sprite.webp> |
| `CompanionAtlas-dog.generated.png` | `aka-shiba` | <https://assets.petdex.dev/pets/aka-shiba-5758e3fbe12c/sprite.webp> |

The source-of-truth list used to rebuild these atlases is
[`Scripts/gen-companion-petdex.py`](Scripts/gen-companion-petdex.py).
