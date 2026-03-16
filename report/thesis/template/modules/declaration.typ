#let declaration-page(body) = {
  pagebreak(weak: true)
  set page(header: none, footer: none)

  align(left)[
    #text(font: ("Open Sans", "Noto Sans"), weight: "bold", size: 18pt)[
      Declaration
    ]
    #v(1.5em)
    #body
    #v(3em)
    #table(
      columns: (1fr, 1fr),
      column-gutter: 1.5cm,
      stroke: none,
      table.cell(inset: (bottom: 0.3em), stroke: (bottom: 0.6pt + black))[],
      table.cell(inset: (bottom: 0.3em), stroke: (bottom: 0.6pt + black))[],
      [Date],
      [Signature],
    )
  ]
}
