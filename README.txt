CAT RUN - Godot 4 project
=========================

KAISE KHOLEIN (phone pe)
1. Yeh zip phone mein extract karo (jaise: Documents/CatRun).
2. Godot kholo -> "Import" -> CatRun folder ke andar "project.godot" chuno -> "Import & Edit".
3. Pehli baar kholne pe Godot thodi der assets import karega (billi ka model). Rukna.
4. Upar ▶ (Play / F5) dabao. Game chalega.

CONTROLS
- Swipe left/right : lane badlo
- Swipe up         : jump
- Swipe down       : slide (hawa mein ho toh jaldi neeche aao)
- PC pe: Arrow keys / WASD / Space

APNE ASSETS (assets/ folder mein, bilkul inhi naamon se)
- cat.glb            Player (animations: Run, Jump, Slide, Idle)   <-- abhi tumhari billi lagi hai
- fish.glb           Machhli
- obstacle_low.glb   Kood ke paar karne wali barrier (~2m chaudi, ~1m oonchi)
- obstacle_high.glb  Jhuk ke neeche se nikalne wala bar (bar 1.2m se upar)
- obstacle_full.glb  Truck/train (~2m chaudi, ~3m oonchi, 8m lambi; aage ka hissa z=0 pe, peeche -Z ki taraf)
- segment.glb        40m lamba sadak ka tukda (sadak + footpath + deewarein), aage z=0, peeche -Z
File daalte hi game khud use karega. Nahi hai toh placeholder dikhega.

KOI ERROR AAYE
Neeche "Output" ya "Debugger" mein laal text ka screenshot bhej dena.
