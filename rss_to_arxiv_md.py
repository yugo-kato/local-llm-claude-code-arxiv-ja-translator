#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""
Download an arXiv RSS feed and convert all items to per-paper Markdown files.

Default behavior:
  - category: cs.CV
  - source RSS: https://rss.arxiv.org/rss/cs.CV
  - export all RSS items: new / cross / replace / replace-cross
  - do not call arXiv API
  - do not output Comments

Examples:
  # Default: cs.CV RSS -> Markdown for all items
  python rss_to_arxiv_md.py ^
    --output-dir .\paper_info_md

  # astro-ph RSS -> Markdown for all items
  python rss_to_arxiv_md.py ^
    --astro-ph ^
    --output-dir .\paper_info_md

  # Offline test with an already downloaded RSS XML file
  python rss_to_arxiv_md.py ^
    --rss-file astro-ph.txt ^
    --output-dir .\paper_info_md

  # Only new submissions, if needed
  python rss_to_arxiv_md.py ^
    --only-new ^
    --output-dir .\paper_info_md
"""

from __future__ import annotations

import argparse
import html
import re
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from email.utils import parsedate_to_datetime
from pathlib import Path


RSS_NS = {
    "arxiv": "http://arxiv.org/schemas/atom",
    "dc": "http://purl.org/dc/elements/1.1/",
}

DEFAULT_CATEGORY = "cs.CV"
RSS_BASE_URL = "https://rss.arxiv.org/rss/"

# Add/edit names as needed. Unknown categories are left as "code" only.
SUBJECT_NAMES = {
    "astro-ph.CO": "Cosmology and Nongalactic Astrophysics",
    "astro-ph.EP": "Earth and Planetary Astrophysics",
    "astro-ph.GA": "Astrophysics of Galaxies",
    "astro-ph.HE": "High Energy Astrophysical Phenomena",
    "astro-ph.IM": "Instrumentation and Methods for Astrophysics",
    "astro-ph.SR": "Solar and Stellar Astrophysics",
    "cs.AI": "Artificial Intelligence",
    "cs.CV": "Computer Vision and Pattern Recognition",
    "cs.LG": "Machine Learning",
    "cs.RO": "Robotics",
    "cs.CL": "Computation and Language",
    "cs.DB": "Databases",
    "gr-qc": "General Relativity and Quantum Cosmology",
    "hep-ph": "High Energy Physics - Phenomenology",
    "hep-th": "High Energy Physics - Theory",
    "hep-ex": "High Energy Physics - Experiment",
    "math-ph": "Mathematical Physics",
    "nlin.PS": "Pattern Formation and Solitons",
    "nucl-th": "Nuclear Theory",
    "physics.plasm-ph": "Plasma Physics",
}


@dataclass
class Paper:
    number: int
    section: str
    listing_date: str
    arxiv_id: str
    version: str
    title: str
    authors: str
    abstract: str
    categories: list[str]
    announce_type: str
    abs_url: str
    primary_category: str = ""


def http_get_text(url: str, timeout: int = 60) -> str:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "arxiv-rss-to-md/1.1 (local research script)",
        },
    )
    with urllib.request.urlopen(req, timeout=timeout) as r:
        data = r.read()
    return data.decode("utf-8", errors="replace")


def parse_rss_date(date_text: str | None) -> str:
    if not date_text:
        return ""
    try:
        dt = parsedate_to_datetime(date_text)
        return dt.strftime("%A, %d %B %Y")
    except Exception:
        return date_text


def clean_text(s: str | None) -> str:
    if not s:
        return ""
    s = html.unescape(s)
    s = s.replace("\r\n", "\n").replace("\r", "\n")
    s = re.sub(r"[ \t]+", " ", s)
    s = re.sub(r"\n\s+", "\n", s)
    return s.strip()


def parse_description(description: str) -> tuple[str, str, str, str]:
    """
    RSS description format is typically:
      arXiv:2605.26138v1 Announce Type: new
      Abstract: ...
    Returns: arxiv_id, version, announce_type, abstract
    """
    text = clean_text(description)
    m = re.search(
        r"arXiv:(?P<id>\d{4}\.\d{4,5})(?P<version>v\d+)\s+"
        r"Announce Type:\s*(?P<announce>[^\n]+)\s*"
        r"Abstract:\s*(?P<abstract>.*)",
        text,
        flags=re.DOTALL,
    )
    if not m:
        return "", "", "", text

    return (
        m.group("id"),
        m.group("version"),
        clean_text(m.group("announce")),
        clean_text(m.group("abstract")),
    )


def section_from_announce(announce_type: str) -> str:
    a = (announce_type or "").strip().lower()
    if a == "new":
        return "New submissions"
    if a == "cross":
        return "Cross-lists"
    if a in {"replace", "replace-cross"}:
        return "Replacements"
    return announce_type or "Unknown"


def subject_label(code: str) -> str:
    name = SUBJECT_NAMES.get(code)
    return f"{name} ({code})" if name else code


def rss_url_for_category(category: str) -> str:
    return RSS_BASE_URL + category


def parse_rss(xml_text: str, only_new: bool = False) -> list[Paper]:
    root = ET.fromstring(xml_text)
    channel = root.find("channel")
    if channel is None:
        raise ValueError("RSS channel element was not found.")

    listing_date = parse_rss_date(channel.findtext("pubDate") or channel.findtext("lastBuildDate"))

    papers: list[Paper] = []
    number = 1

    for item in channel.findall("item"):
        title = clean_text(item.findtext("title"))
        abs_url = clean_text(item.findtext("link"))
        description = item.findtext("description") or ""

        arxiv_id, version, announce_from_desc, abstract = parse_description(description)

        announce_el = item.find("arxiv:announce_type", RSS_NS)
        announce_type = clean_text(announce_el.text if announce_el is not None else "") or announce_from_desc

        if only_new and announce_type.lower() != "new":
            continue

        categories = [clean_text(c.text) for c in item.findall("category") if clean_text(c.text)]
        authors_el = item.find("dc:creator", RSS_NS)
        authors = clean_text(authors_el.text if authors_el is not None else "")

        if not arxiv_id and abs_url:
            m = re.search(r"/abs/(\d{4}\.\d{4,5})(v\d+)?", abs_url)
            if m:
                arxiv_id = m.group(1)
                version = m.group(2) or ""

        papers.append(
            Paper(
                number=number,
                section=section_from_announce(announce_type),
                listing_date=listing_date,
                arxiv_id=arxiv_id,
                version=version,
                title=title,
                authors=authors,
                abstract=abstract,
                categories=categories,
                announce_type=announce_type,
                abs_url=abs_url or f"https://arxiv.org/abs/{arxiv_id}",
                primary_category=categories[0] if categories else "",
            )
        )
        number += 1

    return papers


def markdown_for_paper(p: Paper) -> str:
    primary = p.primary_category or (p.categories[0] if p.categories else "")
    subjects = "; ".join(subject_label(c) for c in p.categories)
    html_url = f"https://arxiv.org/html/{p.arxiv_id}{p.version or 'v1'}"
    pdf_url = f"https://arxiv.org/pdf/{p.arxiv_id}"
    format_url = f"https://arxiv.org/format/{p.arxiv_id}"

    lines = [
        f"# [{p.number}] {p.title}",
        "",
        f"- **Number:** {p.number}",
        f"- **Section:** {p.section}",
        f"- **Listing date:** {p.listing_date}",
        f"- **arXiv:** [{p.arxiv_id}]({p.abs_url})",
        f"- **Authors:** {p.authors}",
        f"- **Primary subject:** {subject_label(primary) if primary else ''}",
        f"- **Subjects:** {subjects}",
        f"- **PDF:** {pdf_url}",
        f"- **HTML:** {html_url}",
        f"- **Other formats:** {format_url}",
        "",
        "## Abstract",
        "",
        p.abstract,
        "",
    ]
    return "\n".join(lines)


def safe_md_filename(number: int, arxiv_id: str) -> str:
    return f"{number:03d}_{arxiv_id or 'unknown'}.md"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Download an arXiv RSS feed and write one Markdown file per paper."
    )
    src = parser.add_mutually_exclusive_group()
    src.add_argument("--rss-url", help="Explicit RSS URL, e.g. https://rss.arxiv.org/rss/astro-ph")
    src.add_argument("--rss-file", help="Existing RSS XML file")

    parser.add_argument("--output-dir", required=True, help="Directory for per-paper Markdown files")
    parser.add_argument("--category", default=DEFAULT_CATEGORY, help="RSS category; default: cs.CV")
    parser.add_argument("--astro-ph", action="store_true", help="Use https://rss.arxiv.org/rss/astro-ph")
    parser.add_argument("--only-new", action="store_true", help="Export only announce_type=new items")
    parser.add_argument("--save-rss", help="Optional path to save the downloaded RSS XML")
    parser.add_argument("--clear-output-dir", action="store_true", help="Delete existing *.md files in output-dir before writing")
    args = parser.parse_args()

    if args.rss_file:
        source_desc = args.rss_file
        xml_text = Path(args.rss_file).read_text(encoding="utf-8", errors="replace")
    else:
        category = "astro-ph" if args.astro_ph else args.category
        rss_url = args.rss_url or rss_url_for_category(category)
        source_desc = rss_url
        xml_text = http_get_text(rss_url)
        if args.save_rss:
            rss_path = Path(args.save_rss)
            rss_path.parent.mkdir(parents=True, exist_ok=True)
            rss_path.write_text(xml_text, encoding="utf-8")

    papers = parse_rss(xml_text, only_new=args.only_new)

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    if args.clear_output_dir:
        for md_path in out_dir.glob("*.md"):
            md_path.unlink()

    for p in papers:
        path = out_dir / safe_md_filename(p.number, p.arxiv_id)
        path.write_text(markdown_for_paper(p), encoding="utf-8")

    print(f"Source: {source_desc}")
    print(f"Markdown files written: {len(papers)}")
    print(f"Output directory: {out_dir}")


if __name__ == "__main__":
    main()
