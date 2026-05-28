TEX = main
LATEX = pdflatex
BIBTEX = bibtex

.PHONY: all clean clean-aux

all: $(TEX).pdf clean-aux

$(TEX).pdf: $(TEX).tex main.bib
	$(LATEX) $(TEX)
	$(BIBTEX) $(TEX)
	$(LATEX) $(TEX)
	$(LATEX) $(TEX)

clean-aux:
	rm -f $(TEX).aux $(TEX).bbl $(TEX).blg $(TEX).log $(TEX).out missfont.log

clean: clean-aux
	rm -f $(TEX).pdf
