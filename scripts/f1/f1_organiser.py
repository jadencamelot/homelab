#!/usr/bin/env python3

import argparse
import os
import re
from dataclasses import dataclass
from pathlib import Path

import requests


@dataclass
class F1FileInfo:
    n: int
    year: int
    round_no: int
    name: str          # e.g. "Japanese Grand Prix"
    session: str       # e.g. "Free Practice One"
    original_path: Path

    @property
    def episode(self) -> int:
        mapping = {
            # Practice
            "free practice": 1,  # Sprint weekends only
            "free practice one": 1,
            "free practice two": 2,
            "free practice three": 3,

            # Sprints
            "sprint qualifying": 2,
            "sprint shootout": 2,
            "sprint": 3,
            "sprint race": 3,

            # Main Event
            "qualifying": 4,
            "race": 5,
        }
        return mapping.get(self.session.lower())

    @property
    def is_special(self) -> bool:
        return self.episode is None

    @property
    def is_interview(self) -> bool:
        return any(x in self.session.lower() for x in ["press", "conference", "interview"])

    @property
    def parent_folder(self) -> str:
        return f"Season {self.round_no:02d} - {self.name}"

    @property
    def subfolder(self) -> str:
        if self.episode:
            return ""
        return "interviews" if self.is_interview else "extras"

    @property
    def new_filename(self) -> str:
        if self.episode:
            return f"{self.session} - {self.name} S{self.round_no:02d}E{self.episode:02d} 1080P.mkv"
        else:
            return f"{self.session} - {self.name} 1080P.mkv"

    @property
    def formatted_path(self) -> Path:
        parts = [self.parent_folder]
        if self.subfolder:
            parts.append(self.subfolder)
        parts.append(self.new_filename)
        return Path(*parts)


def parse_filename(filepath: Path) -> list[str]:
    filename = Path(filepath).name
    pattern = re.compile(
        r'^(?P<n>\d{2})\.F1\.(?P<year>\d{4})\.(?P<round>R\d{2})\.(?P<body>.+?)\.SkyF1HD\.1080P\.mkv',
        re.IGNORECASE
    )

    m = pattern.search(filename)
    if not m:
        return None

    return m.groupdict()


def parse_parent_folder_name(filepath: Path) -> list[str]:
    parent_folder = Path(filepath).parent.name
    pattern = re.compile(
        r'^F1\.(?P<year>\d{4})\.(?P<round>R\d{2})\.(?P<body>.+?)\.SkyF1HD\.1080P',
        re.IGNORECASE
    )

    m = pattern.search(parent_folder)
    if not m:
        return None

    return m.groupdict()


def get_f1_file_info(filepath: str | Path) -> F1FileInfo | None:
    info = parse_filename(filepath)
    parent_info = parse_parent_folder_name(filepath)

    if not info or not parent_info:
        return None

    parts = [p for p in info["body"].split(".") if p]
    parent_parts = [p for p in parent_info["body"].split(".") if p]

    # Find "Grand Prix" boundary
    if "Grand" in parts and "Prix" in parts:
        i = parts.index("Grand")
        name = " ".join(parts[:i + 2])
        name_end = parts[i + 1]
    elif "Grand" in parent_parts and "Prix" in parent_parts:
        # Fall back to using the parent
        i = parent_parts.index("Grand")
        name = " ".join(parent_parts[:i + 2])
        name_end = parent_parts[i - 1]  # Exclude "Grand Prix" since it's missing from the filename
    else:
        # If "Grand Prix" is missing entirely, assume the name is the full body of the parent (e.g. Emilia.Romagna)
        name = " ".join(parent_parts) + " Grand Prix"
        name_end = parent_parts[-1]  # Exclude "Grand Prix" since it's missing from the filename
    j = parts.index(name_end) if name_end in parts else 0
    session = " ".join(parts[j + 1:])

    return F1FileInfo(
        n=int(info["n"]),
        year=int(info["year"]),
        round_no=int(info["round"][1:]),  # R03 -> 3
        name=name,
        session=session,
        original_path=Path(filepath),
    )


def OLD_parse_filename(filepath: str | Path) -> F1FileInfo | None:
    filename = Path(filepath).name
    pattern = re.compile(
        r'^(?P<n>\d{2})\.F1\.(?P<year>\d{4})\.(?P<round>R\d{2})\.(?P<body>.+?)\.SkyF1HD\.1080P\.mkv',
        re.IGNORECASE
    )

    m = pattern.search(filename)
    if not m:
        return None

    info = m.groupdict()
    parts = [p for p in info["body"].split(".") if p]
    parent_parts = [p for p in filepath.parent.name.split(".") if p]

    # Find "Grand Prix" boundary
    if "Grand" in parts and "Prix" in parts:
        i = parts.index("Grand")
        name = " ".join(parts[:i+2])
        session = " ".join(parts[i+2:])  
    elif "Grand" in parent_parts and "Prix" in parent_parts:
        i = parent_parts.index("Grand")
        name = " ".join(parent_parts[:i + 2])
        j = parts.index(name) if name in parts else 0
        session = " ".join(parts[j:])
    else:
        # If "Grand Prix" is missing, assume the name is the first 2 tokens (e.g. Emilia.Romagna)
        name = " ".join(parts[:2]) + " Grand Prix"
        session = " ".join(parts[2:])

    return F1FileInfo(
        n=int(info["n"]),
        year=int(info["year"]),
        round_no=int(info["round"][1:]),  # R03 -> 3
        name=name,
        session=session,
        original_path=Path(filepath),
    )


def fetch_sportsdb_info(year: int, round_no: int):
    url = (f"https://www.thesportsdb.com/api/v1/json/3/eventsround.php?id=4370"
           f"&r={round_no}&s={year}")
    r = requests.get(url, timeout=10)
    if not r.ok or not (data := r.json()):
        return None
    return data.get("events")


def fetch_thumbnail_for_episode(info: F1FileInfo, dest_folder: Path, dry_run: bool = False):
    thumb_path = dest_folder / (info.new_filename.replace(".mkv", "-thumb.jpg"))
    if thumb_path.exists():
        return

    if dry_run:
        print(f"[DRY-RUN] Thumbnail: {thumb_path}")
        return

    sportsdb_info = fetch_sportsdb_info(info.year, info.round_no)
    if not sportsdb_info or not info.episode or len(sportsdb_info) < info.episode:
        return
    sportsdb_event = sportsdb_info[info.episode - 1]  # SportsDB indexes sessions beginning at zero

    if not (thumb_url := sportsdb_event.get("strThumb")):
        return

    r = requests.get(thumb_url, stream=True, timeout=10)
    if not r.ok:
        return

    with open(thumb_path, "wb") as f:
        for chunk in r.iter_content(8192):
            f.write(chunk)
    
    print(f"[THUMB] {thumb_url}\n"
          f"     -> {thumb_path}")


def fetch_season_poster(info: F1FileInfo, dest_folder: Path, dry_run: bool = False):
    """
    Fetch the race poster for a GP season from eventartworks.de and save it as poster.webp
    in the season folder.
    """
    season_folder = dest_folder / info.parent_folder
    poster_path = season_folder / "poster.webp"

    if poster_path.exists():
        # print(f"[SKIP] Poster already exists: {poster_path}")
        return

    base_url = "https://www.eventartworks.de"
    poster_url_map = {
        1: "images/f1@1200/2025-03-16-melbourne.webp",
        2: "images/f1@1200/2025-03-23-shanghai.webp",
        3: "images/f1@1200/2025-04-06-suzuka.webp",
        4: "images/f1@1200/2025-04-13-sakhir.webp",
        5: "images/f1@1200/2025-04-20-jeddah.webp",
        6: "images/f1@1200/2025-05-04-miami.webp",
        7: "images/f1@1200/2025-05-18-imola.webp",
        8: "images/f1@1200/2025-05-25-montecarlo.webp",
        9: "images/f1@1200/2025-06-01-barcelona.webp",
        10: "images/f1@1200/2025-06-15-montreal.webp",
        11: "images/f1@1200/2025-06-29-spielberg.webp",
        12: "images/f1@1200/2025-07-06-silverstone.webp",
        13: "images/f1@1200/2025-07-27-spa-francorchamps.webp",
        14: "images/f1@1200/2025-08-03-budapest.webp",
        15: "images/f1@1200/2025-08-31-zandvoort.webp",
        16: "images/f1@1200/2025-09-07-monza.webp",
        17: "images/f1@1200/2025-09-21-baku.webp",
        18: "images/f1@1200/2025-10-05-singapore.webp",
        19: "images/f1@1200/2025-10-19-austin.webp",
        20: "images/f1@1200/2025-10-26-mexico.webp",
        21: "images/f1@1200/2025-11-09-interlagos.webp",
        22: "images/f1@1200/2025-11-22-lasvegas.webp",
        23: "images/f1@1200/2025-11-30-lusail.webp",
        24: "images/f1@1200/2025-12-07-abudhabi.webp",
    }

    if info.round_no not in poster_url_map:
        print(f"[WARN] No poster found for round {info.round_no}")
        return

    url = f"{base_url}/{poster_url_map[info.round_no]}"

    if dry_run:
        print(f"[DRY-RUN] Would fetch poster: {url}\n"
              f"                           -> {poster_path}")
        return

    # Download the poster
    try:
        r = requests.get(url, timeout=15)
        r.raise_for_status()
    except requests.RequestException as e:
        print(f"[ERROR] Could not download poster from {url}: {e}")
        return

    with open(poster_path, "wb") as f:
        for chunk in r.iter_content(8192):
            f.write(chunk)

    print(f"[POSTER] Downloaded: {poster_path}")


def write_nfo_for_episode(info: F1FileInfo, dest_folder: Path, dry_run: bool = False):
    """
    Generate a minimal .nfo file for Jellyfin for this F1 session.
    The file will sit alongside the MKV with the same basename.
    """
    if not info.episode:
        return  # Only create NFO for competitive sessions (with episode numbers)

    nfo_path = dest_folder / (info.new_filename.replace(".mkv", ".nfo"))

    episode_title = f"{info.session} - {info.name}"
    round_title = f"{info.round_no}. {info.name.replace("Grand Prix", "GP")}"

    # NFO format Jellyfin can understand for a TV episode
    nfo_content = f"""<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>
<episodedetails>
  <title>{episode_title}</title>
  <showtitle>{round_title}</showtitle>
  <season>{info.round_no}</season>
  <episode>{info.episode}</episode>
  <year>{info.year}</year>
</episodedetails>
"""

    if nfo_path.exists():
        return

    if dry_run:
        print(f"[DRY-RUN] Would write NFO: {nfo_path}")
        print(nfo_content)
        return

    with open(nfo_path, "w", encoding="utf-8") as f:
        f.write(nfo_content)
    
    print(f"[NFO] Written: {nfo_path}")


def write_nfo_for_season(info: F1FileInfo, dest_folder: Path, dry_run: bool = False):
    """
    Generate a season-level NFO for Jellyfin. This describes the whole GP round.
    The NFO goes in the season folder (parent folder of episodes).
    """
    season_folder = dest_folder / info.parent_folder
    nfo_path = season_folder / "season.nfo"

    season_title = f"{info.round_no}. {info.name.replace('Grand Prix', 'GP')}"
    show_title = f"F1 {info.year} Season"

    # Minimal NFO for Jellyfin
    nfo_content = f"""<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>
<tvshow>
  <title>{season_title}</title>
  <season>{info.round_no}</season>
  <year>{info.year}</year>
</tvshow>
"""

    if nfo_path.exists():
        return

    if dry_run:
        print(f"[DRY-RUN] Would write season NFO: {nfo_path}")
        print(nfo_content)
        return

    season_folder.mkdir(parents=True, exist_ok=True)
    with open(nfo_path, "w", encoding="utf-8") as f:
        f.write(nfo_content)

    print(f"[SEASON NFO] Written: {nfo_path}")



def process_file(file_path: Path, output_root: Path, round_no: int | None = None, dry_run: bool = False):
    if not (info := get_f1_file_info(file_path)):
        print(f"[SKIP] Unrecognized file: {file_path}")
        return

    if round_no and round_no != info.round_no:
        return

    dest_path = output_root / info.formatted_path
    if not dry_run:
        dest_path.parent.mkdir(parents=True, exist_ok=True)

    # Create hard link if needed
    if dest_path.exists():
        # print(f"[SKIP] Already linked: {dest_path}")
        pass
    elif dry_run:
        print(f"[DRY-RUN] Would link: {file_path}\n"
              f"                   -> {dest_path}")
    else:
        os.link(file_path, dest_path)
        print(f"[LINKED] {file_path}\n"
              f"      -> {dest_path}")

    # If this is a competitive session (has an episode number), fetch the thumbnail and create .nfo file
    if info.episode:
        fetch_thumbnail_for_episode(info, dest_path.parent, dry_run)
        write_nfo_for_episode(info, dest_path.parent, dry_run)
        season_folder = dest_path.parent
        write_nfo_for_season(info, dest_path.parent.parent, dry_run)

    # Create season.nfo and fetch season poster
    season_folder = dest_path.parent.parent if info.episode else dest_path.parent.parent.parent
    write_nfo_for_season(info, season_folder, dry_run)
    fetch_season_poster(info, season_folder, dry_run)


def main():
    parser = argparse.ArgumentParser(
        description="Reformat F1 file names, create hard links, and download thumbnails."
    )
    parser.add_argument("input_folder", help="Path to input folder containing source MKVs")
    parser.add_argument("output_folder", help="Path to output folder for reformatted structure")
    parser.add_argument("--dry-run", action="store_true",
                        help="Show what would be done without making any filesystem or network changes",
    )
    parser.add_argument("--round", type=int,
                        help="Only process files from this round of the F1 championship")
    args = parser.parse_args()

    input_root = Path(args.input_folder)
    output_root = Path(args.output_folder)

    for file_path in input_root.rglob("*.mkv"):
        process_file(file_path, output_root, round_no=args.round, dry_run=args.dry_run)


if __name__ == "__main__":
    main()
