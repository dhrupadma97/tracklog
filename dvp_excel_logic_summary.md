# Goodyear DVP Test Case Generation & Mapping Summary

This document summarizes the logic, mappings, and formatting rules established for the **Goodyear DVP (Calibration and Validation)** test cases. It can be shared directly with the agent working on the Web App to provide complete context on how the data is structured and generated.

## 1. Project Structure & Terminology
The repository structures test cases hierarchically:
*   **Project Types:** EV (Electric Vehicle) vs. ICE (Internal Combustion Engine)
*   **Activity Types:** Validation (Final Acceptance) vs. Calibration (Threshold tuning/characterization)
*   **Features:** AQD (Aquaplaning), DFE (Dynamic Friction Estimation), Leak Detection, etc.

---

## 2. Validation Test Cases (AQD)
**Source:** Appended to the original `9.Test Cases_AQD` sheet.
*   **Total Test Cases:** 780 unique cases.
*   **Additions (GY.SL.AQD.685 – 780):** 
    *   **Double Lane Change (DLC):** Testing AQD behavior during lateral maneuvers.
    *   **ICE False Positives:** Non-regen specific transients (gear shifts, tip-in/tip-out, engine braking, coasting) to ensure AQD doesn't falsely trigger on ICE drivetrains.
    *   **Hump Road / Ride Quality:** Speed breakers, cleats, rumble strips, and undulating roads to verify structural/vertical excitations don't cause false positives.
*   **Separation:** Explicit bifurcation of EV vs. ICE conditions so algorithmic tuning teams can isolate drivetrain differences.

---

## 3. Calibration Test Cases (AQD)
**Source:** Extracted from `Mahindra Calibration.xlsx` (AQD Sheet) and mapped to Goodyear standard.
*   **Test Cases (GY.SL.AQD.CAL.1+):**
    *   Grouped by water depths: **4mm** and **8mm**.
    *   Scenarios: Straight Constant speed, Straight Acceleration, Braking (Straightline), Braking (Curve).
    *   Speeds range from 40 kph up to 105 kph depending on the maneuver.
*   **Purpose:** Establishes threshold characterizations, surface sensitivities, and false-positive baselines for the AQD algorithm.

---

## 4. DFE Calibration & Validation
**Source:** `DFE_DVP_TCs.xlsx`
*   **DFE Calibration (`9.Test Cases_DFE_CAL`):** 11 Test cases mapping specific surfaces (Jump Mu, Split Mu, Dry, Wet Basalt, Wet Ceramic) across various speeds and loads to calibrate surface estimation thresholds.
*   **DFE Validation (`9.Test Cases_DFE`):** 47 Test cases covering varied maneuvers (Cruising, Light/Heavy Acceleration, Light/Heavy Braking) across Jump Mu and Split Mu to validate the surface estimation model accuracy.

---

## 5. Leak Detection Calibration
**Source:** `Mahindra Calibration.xlsx` (Leak Detection Sheet)
*   **Leak Calibration (`9.Test Cases_Leak_CAL`):** 10 Test cases mapping specific Leak Rates (ranging from 1000 up to 30000) against Interval limits (375ms to 13250ms).

---

## 6. Goodyear Visual Formatting Standards
All Python scripts manipulating the Excel data strictly adhere to the following visual aesthetic to match the original Goodyear team format:

*   **Main Title (Row 1):**
    *   Font: Arial, 14pt, Bold, Color: Gold (`FFC6A15B`)
    *   Fill: Dark Navy (`FF0A2342`)
*   **Subtitle (Row 2):**
    *   Font: Arial, 9pt, Color: White (`FFFFFFFF`)
    *   Fill: Navy (`FF12325C`)
*   **Scope Headers (Rows 5, 6, 10):**
    *   Label Font: Barlow, 12pt, Bold, Color: Black. Fill: Cream (`FFECE3CE`)
    *   Description Font: Barlow, 12pt, Regular, Color: Black. Fill: White (`FFFFFFFF`)
*   **Column Headers (Rows 11-13):**
    *   Font: Arial, 10pt, Bold, Color: Gold (`FFC6A15B`)
    *   Fill: Navy (`FF12325C`)
*   **Data Rows:**
    *   Font: Calibri, 11pt, Regular, Color: Default (Black)
    *   Borders: Thin continuous borders on all sides.
*   **Group Headers (In-table breaks):**
    *   Font: Calibri, 11pt, Bold, Color: Red (`FF0000`)
    *   Sub-group Headers: Calibri, 11pt, Bold Italic, Color: Blue (`0070C0`)

---

## 7. Column Data Structure
To ensure consistent parsing into JSON/Web Apps, the 11 standardized columns are:
1.  **Test Id** (e.g., `GY.SL.AQD.1` or `GY.SL.DFE.CAL.1`)
2.  **Test Cases Name** (Description of maneuver/condition)
3.  **Tire Type** (e.g., SKU-21)
4.  **Tire Condition** (e.g., New / Full Worn)
5.  **Tire Pressure** (e.g., Standard pressure-0.5)
6.  **Road Surface** (e.g., Asphalt - 4mm, Wet Basalt)
7.  **Load** (e.g., Driver Only, Full)
8.  **Test Description** (Detailed test procedure / expected results)
9.  **Test Case Link** (Optional)
10. **Test Result** (Optional)
11. **Comments** (Optional)
