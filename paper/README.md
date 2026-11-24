# HeadProbe paper (draft)

IEEE conference template (`IEEEtran` v1.8b, two-column, US letter), the same template as the PerCom
Work-in-Progress track. Currently **5 pages including references**. Check the target venue's page
limit: PerCom WiP papers were limited to 4 pages including references.

## Status: every participant result is a placeholder

No data have been collected. Everything in **red** is a placeholder: participant numbers, statistics,
measured timing, figures 2-4 and table II. The results paragraphs are written in the direction the
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
- **Tectonic:** `tectonic main.tex` (the preamble switches to a Times clone under XeTeX).

## Before submitting

- [ ] Authors, affiliations, emails (red TODOs at the top).
- [ ] Ethics approval reference in the Discussion.
- [ ] The "Lapse" measure in Table I needs a per-person threshold rule; it is not in the analysis
      script yet (decide it before looking at the data).
- [ ] Left/right bias analysis (Study 2) is not in the analysis script yet.
- [ ] Every citation was matched to Crossref on 2026-11-24 (see the header of `refs.bib`). The
      descriptions of other papers' findings should be re-read against the papers themselves.
- [ ] Page limit of the target venue.
