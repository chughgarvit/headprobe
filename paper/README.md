# HeadProbe paper (draft)

IEEE conference template (`IEEEtran` v1.8b, two-column, US letter), the same template as the PerCom
Work-in-Progress track.

- `main.tex`: **the PerCom WiP version**. Limit 4 pages including references (every PerCom WiP call
  2021-2026); currently about 2.7 pages, leaving room for real figures and author details. Follows the
  WiP genre: one small pilot (0-back vs 2-back, head turn vs tap, about 10 people), a timing
  characterisation, openly preliminary claims, related work folded into the introduction,
  15 references, numbered next steps. Drowsiness is a planned study, not a result.
- `main_full.tex`: the earlier 5-page version with two full studies (graded load, drowsiness).
  Kept as a starting point for a later full paper. Not for the WiP track.

## Status: every participant result is a placeholder

No data have been collected. Everything in **red** is a placeholder: participant numbers, statistics,
measured timing, the figures and tables. The results paragraphs are written in the direction the
hypotheses predict, so that the structure is ready. When the data are in:

1. Replace each red value with the analysed number.
2. **Rewrite every results sentence to what was actually found**, including null or opposite results,
   and the abstract, discussion and conclusion to match. Do not keep a sentence just because it is
   already written.
3. Delete `\draftbanner{}` in the abstract, and check that no red text is left.

Not placeholders (real): the app's design parameters (150 ms burst, ±30/60/90°, 3-5 s, 2.5 s window,
2°/8°/20°/s/100 ms/250 ms scorer constants) and the scorer validation numbers, which come from
`python analysis/headprobe_analyze.py --selftest`.

## Compile

- **Overleaf:** New Project > Upload Project > the zip. Default compiler (pdfLaTeX) is right.
- **Locally:** `pdflatex main`, `bibtex main`, `pdflatex main`, `pdflatex main`.
- **Tectonic:** `tectonic main.tex` or `tectonic main_full.tex` (the preamble switches to a Times clone under XeTeX).

## Before submitting

- [ ] Authors, affiliations, emails (red TODOs at the top).
- [ ] Ethics approval reference in the Discussion.
- [ ] The "Lapse" measure in Table I needs a per-person threshold rule; it is not in the analysis
      script yet (decide it before looking at the data).
- [ ] Left/right bias analysis (full version, Study 2) is not in the analysis script yet.
- [ ] Consider citing the group's own earable WiPs (e.g. PerCom 2025/2026) as related earable work.
- [ ] Every citation was matched to Crossref on 2026-11-24 (see the header of `refs.bib`). The
      descriptions of other papers' findings should be re-read against the papers themselves.
- [ ] Page limit of the target venue.
