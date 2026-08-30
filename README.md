# iLoca

**Find the right place. Build with confidence.**

iLoca is a macOS app that helps first-time small business owners choose the right location for their business — without needing to be a data analyst to do it.

Built by **Team DuoNode** (Thao Lai & Afrah Khan) for the **Mobile AI Hackathon, August 2026** (RMIT University × Apple Foundation Program).

---

## The Problem

Meet Maya. She's dreaming of opening her first café, and like most first-time founders, she's buried in scattered browser tabs: property listings, competitor maps, footfall data, lease terms, trying to manually compare suburbs with no single source of truth.

The stakes are real. **1 in 4 Australian businesses** don't survive their first year, and half close within three. But founders who start with the right structure and resources are **61%** likely to survive **three years**. Access to the right tools early on decides the success of the business.

## What iLoca Does

iLoca brings all of that scattered research into one place. Instead of manually cross-referencing five different websites, iLoca pulls together:

- Foot traffic patterns
- Nearby competitor density
- Local demographics
- Property listings and lease terms
- Development and building approval activity

...and surfaces it as a single, interactive location-intelligence view, so users can shortlist and book inspections with confidence instead of guesswork.

## How It Works

- **On-device data pipeline:** Raw datasets (property, demographic, and business listing data) are pre-processed and structured using machine learning, so the app can serve clean, relevant insights instead of raw noise.
- **Apple Foundation Models:** iLoca uses Apple's on-device AI Foundation Models to power its reasoning and recommendation layer.
- **No cloud dependency:** This is a fully native macOS app — all AI processing happens **on-device**. Nothing is sent to an external server, which means no cloud costs, no latency waiting on API calls, and no user data leaving the machine.

## Tech Stack

- **Language:** Swift
- **Platform:** macOS (built in Xcode)
- **AI:** Apple Foundation Models (on-device),
- **ML:** ML preprocessing pipeline (Azure, PowerBI, Python) for dataset cleaning/structuring
- **UI:** SwiftUI

## Datasets Used

1. **Blocks for Census of Land Use and Employment (CLUE)** — spatial polygons, the join key for everything else
   https://data.melbourne.vic.gov.au/explore/dataset/blocks-for-census-of-land-use-and-employment-clue/

2. **Business establishments per block by CLUE industry** — block-level competitor counts by ANZSIC
   https://data.melbourne.vic.gov.au/explore/dataset/business-establishments-per-block-by-clue-industry/

3. **Business establishments with address and industry classification** — point-level, for plotting actual dots on the map
   https://data.melbourne.vic.gov.au/explore/dataset/business-establishments-with-address-and-industry-classification/

4. **Pedestrian Counting System** (sensor locations + counts)
   https://www.pedestrian.melbourne.vic.gov.au/ (also on the main portal — search "pedestrian counting system" at data.melbourne.vic.gov.au)

### Future Datasets

5. **Off-street car parks with capacity and type**
   https://data.melbourne.vic.gov.au/explore/dataset/off-street-car-parks-with-capacity-and-type/

6. **On-street parking bays + sensors** — live occupancy, for a "right now" parking signal rather than static capacity
   https://data.melbourne.vic.gov.au/explore/dataset/on-street-parking-bay-sensors/

## Getting Started

### Requirements
- macOS (recent version recommended)
- Xcode (latest stable release recommended)

### Running the app
1. Clone this repository
   ```bash
   git clone https://github.com/curiospace/iLoca.git
   ```
2. Open `iLoca.xcodeproj` in Xcode
3. Build and run (⌘R)

No API keys or external configuration needed — everything runs locally.

## Screenshots

**Home** — Find the right place, build with confidence.
![Home screen](screenshots/home.png)

**Map** — Interactive 3D block-level view with opportunity scoring, footfall, competitor density, and nearby businesses.
![Map screen](screenshots/map.png)

**Guide** — On-device AI assistant that answers setup, budget, and growth questions for Melbourne CBD businesses.
![Guide screen](screenshots/guide.png)

## Team

Built by **DuoNode**:
- Thao Lai
- Afrah Khan

Made for the Mobile AI Hackathon, August 2026 — RMIT University × Apple Foundation Program.
