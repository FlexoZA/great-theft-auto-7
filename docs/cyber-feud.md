# Cyber Feud design

A quest line in the shape of A-Man's (`src/features/a-man`): a job on the
board, five maps chained by each quest's `next`, an intro screen, chatter, and
a boss at the end. The look is cyberpunk, neon on grey, in that style rather
than a parody of any one game.

Status: story and structure agreed. Characters, maps and tuning come next.

## Decisions

| Question | Decision |
| --- | --- |
| Whose side are you on? | **Nobody's, and nobody is on yours.** No faction choice, no branching. Both factions want you dead, and so does your fixer. |
| Parody or its own thing? | **Its own thing in the style.** Original names, no direct jokes on one game the way A-Man is on Half-Life. |
| How long? | **Five maps**, like A-Man's trail. |
| Does VEX die? | **No. She escapes into the net** at the end, to set up a sequel quest line. |
| What happens to the Shard? | **Undecided.** Keep it, broadcast it, or something else. It decides the last screen's line and maybe the reward (see "Open questions"). |

## Logline

Grey City has two powers, and they've been at war for 40 years. You're a
nobody courier, and you just picked up the one thing that proves the war is
staged. Now both sides want you dead, and so does the voice in your dashboard.

## The cast

None of them are on your side.

- **VEX**, your fixer. A voice and a glitching face that lives in your car's
  dashboard. She gave you the job, she talks you through every level, and she
  sounds like she's helping. She isn't: she sells your location to whoever
  pays most, and every "helpful tip" comes just before a wave arrives. She
  fills A-Man's role in the quest: the intro screen portrait (glitching where
  his jumps), the chatter, and the last word. Colour: sickly green.
- **Halcyon Dynamics**, the corporation. Grey suits, drones, turrets, polite
  and clinical. Colour: magenta on grey.
  - **Director Saye**, its head. No visible implants, and somehow the
    scariest one in the city.
- **The Static**, the street. A gang more machine than people: shotguns,
  cyber-limbs, war-rigs. Colour: cyan on chrome.
  - **Kilowatt**, its leader. Loud, huge, with a reactor where a heart used
    to be.
- **The Shard**, the package. A data chip holding a recording of Saye and
  Kilowatt splitting the profits from 40 years of selling weapons to each
  other. The feud is a business, and you're holding the receipts.

## Character design

### VEX

**Who she is.** A fixer nobody has met in person, and nobody alive ever
will. Years ago she uploaded herself and kept the business. She lives in
whatever is connected: your car's dashboard, the market's screens, the
tower's systems, and at the end the net itself. She doesn't hate you. You
are a job, and jobs have margins. She calls you "courier" and never by name.

**Portrait** (64x72, primitives on a canvas scaled up with nearest
filtering, like `a-man/face.lua`): a hologram on a dashboard screen, head and
shoulders.

- Hair: a hard-cut black bob with a green sheen, long on her left and down
  past the jaw, shaved to stubble on her right. Blunt fringe down to the
  brows.
- Face: pale, grey-green under the hologram's tint, narrow and calm.
- Eyes: her left one is natural and dark. Her right one is a ring optic that
  glows green with a bright pinpoint.
- Mouth: a thin smile, a little too wide, that never moves much.
- A data-port tattoo: a green circuit line running from the corner of her
  mouth down to her chin.
- Collar: a high-necked dark jacket with glowing green seams.
- Over it all: a faint green wash, rolling scanlines, and now and then a
  slice of her slipping sideways.

| Colour | Use |
| --- | --- |
| `#08110d` | screen behind her |
| `#b8c6bc` / `#8d9c92` | skin, shade |
| `#0e1d17` / `#25463a` | hair, its sheen |
| `#4a5c53` | the shaved side |
| `#262c30` / `#171b1e` | jacket |
| `#6dff9a` | optic, seams, tattoo, scanline wash (her green) |
| `#ff3ec8` | the tell when she sells you to Halcyon |
| `#2ee6ff` | the tell when she sells you to the Static |

**Animation.** Blinks; her natural eye glances, the optic never moves. Small
slices slip sideways now and then. While she talks, a slice slips on each
emphasised word. She freezes for a few frames now and then, as if buffering.

**The tell (gameplay).** When she sells your location, a ghost of her splits
off in the buyer's colour (magenta for Halcyon, cyan for the Static) and her
slices jitter harder, for a second or two, while she keeps talking as if
nothing happened. A few seconds later that faction's wave arrives. New players
read it as a glitch; those who have learnt it get a warning and the colour of
who is coming. The tell is the story told through the HUD: she is lying to
you, and the screen shows it.

**Voice.** Warm, quick, reassuring, a customer-service tone. Short sentences.
She praises you a lot. She is always eating something or doing something else
while you are being shot at. Her lies are specific and confident; her truths
come out as asides. Her sound is a soft modem chirp with a falling pitch at
the end of each line, on its own sound channel.

**Chatter** (picked by category and index on the host, like
`a-man/radio.lua`; it shows on the HUD next to her small portrait, not over
anyone's head):

| Category | When | Examples |
| --- | --- | --- |
| `tip` | Before a wave, often with the tell | "Take the left exit, courier. It's quiet." / "Nobody uses the service stairs. Trust me." / "Park it there. Safest block in the city." |
| `praise` | A wave cleared | "Look at you. Five stars." / "See? I told you that'd work out." / "That's why I hire the best. Well, the available." |
| `aside` | Now and then, the truth slipping out | "...yes, eastbound, grey car. Oh. You're still on?" / "Sorry, other call. Unrelated." / "Hold on, someone's bidding. Not on you." |
| `down` | A player goes down | "Oof. I'll put that on your tab." / "Get up. The job's not done and neither are you." |
| `breach` | A player starts a breach | "Easy, that's my network you're poking." / "Need a hand? No? Fine." |
| `callback` | When a lie is found out | "In fairness, it was quiet. Before." / "Okay, *mostly* safe." |

**Intro screen lines** (one per level; the quest picks by index, like
`a-man/screen.lua`):

1. The Drop: "Hey, courier. Nice car. I'm in it now. Drive."
2. The Market: "Crowded in there. Good. Crowds are safe. Usually."
3. The Overpass: "I found you a shortcut. You're going to love it."
4. Halcyon Tower: "Their security is a mess. I'll get you in. Getting out is on you."
5. The Roof: "Funny thing about the receipts, courier. My name's on them too."

**Her arc, level by level.**

| Level | Where she lives | What she does |
| --- | --- | --- |
| 1 | Your dashboard | Boots up mid-chase, friendly. First tell at the end; few will notice. |
| 2 | The market's screens too | Tips, praise, tells before each wave. Her face appears on the stall screens around you. |
| 3 | The overpass's signs | The shortcut. Her biggest lie, and the first ambush with both sides waiting together. |
| 4 | The tower's systems | Guides you floor by floor; the doors she opens lead to rooms full of guards. She stops pretending much. |
| 5 | The roof's screens, then the net | Drops the act. The last fight. |

**On the Roof.** When Saye and Kilowatt are down, VEX locks the roof and comes
up huge: her face projected over the whole roof, in green with both tells
flickering at once. She can't be shot. She drives the tower's turrets, and
relay terminals around the edge of the roof keep her there. Players breach
the relays one by one while the turrets fire; she moves between the ones
left, and her portrait breaks up more with each one lost (more slips, colour
dropping out, frames missing). On the last relay she gets away: her face
shrinks to a single green pixel that streaks off the edge of the screen,
leaving her last line in the bubble: "Nothing personal, courier." She is
never beaten for good; the sequel picks her up.

### Director Saye

**Who she is.** Head of Halcyon Dynamics for 40 years and somehow not a day
older. Calm, precise, never raises her voice. People say she's the only
person in Grey City without implants. The truth is that there is nothing left
of her to see: under the skin she is all Halcyon hardware, the best money
can buy, and she has kept a human face because it's good for business.

**Portrait** (64x72): head and shoulders, front on, perfectly still.

- Hair: short, swept back, silver-white, not a strand out of place.
- Face: pale, smooth, nearly expressionless. Thin rimless glasses that catch
  the light (a pinpoint glint on each lens).
- Mouth: a straight line. The only expression she has is a very slight
  narrowing of the eyes.
- Clothes: a grey suit, a white shirt buttoned to the top, a magenta pocket
  square: the only colour on her, Halcyon's colour.
- Phase 2: her cheek and lapel crack open to brushed chrome, lit magenta
  from inside, and a magenta light comes on behind one lens. Nothing else on
  her face changes.

Her portrait barely moves: an occasional blink, slow and exactly on a
rhythm. The stillness is the point; next to VEX's glitching and Kilowatt's
shaking, she is the frightening one.

| Colour | Use |
| --- | --- |
| `#14121a` | behind her |
| `#ddd6cf` / `#c9c2bc` | skin, shade |
| `#e9e9ee` / `#b9bcc4` | hair, its shade |
| `#6c727a` / `#5a5f66` | suit |
| `#e6e6ea` | shirt |
| `#ff3ec8` | pocket square; the glow under her skin |
| `#9aa0aa` / `#c8cdd5` | chrome under the cracks |

**Voice.** Corporate euphemism for everything, especially violence. She
never threatens; she schedules. She calls players "the contractor".

- "You've been let go."
- "Let's take this offline."
- "I'm afraid your position has been made redundant."
- "Security, please escort the contractor. Permanently."
- "We'll circle back to you." (as she backs off)
- Phase 2: "This is coming out of your severance."
- Down: "Noted."

**In the fight: at range.** She walks, never runs, and keeps her distance.

- **Executive drones**: three small drones orbit her and shoot at whoever is
  nearest (`bullet`). Shoot them down and she calls more after a while.
- **Sightline**: she raises her pistol and a thin magenta line marks where
  her shot is going, for a second. Then a single heavy round down that line
  (`bullet`, hits hard). Step off the line to dodge it.
- **Restructuring**: she drops a sentry turret where she stands and walks
  away from it.
- Phase 2 (half health): her skin cracks. The sightline takes half as long,
  she fires two at once in a V, and she walks faster.

**Before the Roof.** She is on the tower's screens through level 4, talking
to the guards, and to you, about "an unscheduled visitor".

### Kilowatt

**Who he is.** Leader of the Static: huge, loud, and more machine than man.
His heart was replaced with a small reactor years ago and he hasn't slowed
down since. He loves a fight the way other people love a meal. He knows the
feud is a business, and doesn't care: he gets to fight every day and gets
paid for it.

**Portrait** (64x72): fills the frame, leaning in.

- Hair: a mohawk of thick black cables, each with a glowing cyan tip.
- Face: broad, warm brown, heavy brow.
- Eyes: his left one is natural, wide and wild. His right one is a cyan visor
  bar that pulses with his reactor.
- Jaw: the whole lower jaw is chrome, with a grille of steel teeth fixed in
  a grin.
- Body: a neck as wide as his head, and a chrome cage over his chest with
  the reactor glowing cyan inside, pulsing like a heartbeat.
- Phase 2: the reactor runs hot, pulsing fast, cyan arcs spark off his
  cables and shoulders, and the whole portrait shakes.

| Colour | Use |
| --- | --- |
| `#0c1418` | behind him |
| `#7a5a44` / `#6a4c38` | skin, shade |
| `#20262a` | cables |
| `#8a939c` / `#b5bdc4` | chrome jaw, cage |
| `#d8dde2` | teeth |
| `#2ee6ff` / `#c8fbff` | cable tips, visor, reactor, arcs |

**Voice.** Loud. Laughs at everything, including getting shot. Calls players
"spark" and means it fondly, sort of.

- "THERE you are, spark!"
- "Hold still, I just wanna hug you. Hard."
- "Ha! That tickled. Do it again."
- "You run like a corp. Fight like one too?"
- Venting: "Ooh, hot hot hot, gimme a second."
- Phase 2: "Now we're LIT!"
- Down: "...good fight, spark."

**In the fight: up close.**

- **Charge**: he lowers his head and runs at whoever is nearest, a long straight
  line (`impact`). He can't turn once started; side-step it.
- **Ground slam**: a hop and a slam, with a cyan ring of shock rolling out
  (`shock`; jumping it isn't a thing, so be out of reach).
- **Arc whip**: a crackling line from his fist to a target and on to anyone
  near them (`shock`, chains up to 3).
- **Venting**: after every few attacks his chest cage opens and he stands
  steaming for 3 s. Hits on his reactor then do double damage. This is the
  window.
- Phase 2 (half health): no cooldown between charges, the slam's ring
  travels further, and he vents less often but for longer.

**Before the Roof.** He makes a cameo on the Overpass (level 3), riding the
lead war-rig past you, laughing, and leaping off it onto the road as it
crashes.

### Saye and Kilowatt together: the Roof

Two bosses with two health bars, fighting as partners. Their portraits sit
side by side on the boss card when the fight starts.

- **They cover each other.** Shooting Saye sends Kilowatt charging at you;
  standing next to Kilowatt draws Saye's sightline. The way to win is to
  split the group: some keep Kilowatt busy while others take Saye.
- **Shield**: when Kilowatt vents, Saye parks her drones round him as a
  shield. Shoot the drones and the vent window opens properly.
- **When one falls**, the other rages:
  - Saye left alone: "Hostile takeover." Her drones double, and her sightline
    fires in bursts of three.
  - Kilowatt left alone: "MELTDOWN!" Permanent phase 2, and his slams leave
    shock patches on the ground for a few seconds.
- **They bicker.** Forty years of a business partnership come out mid-fight:
  - Kilowatt: "You said this kid was a nobody!" / Saye: "They are. It's a
    very expensive nobody."
  - Saye: "Your people destroyed my lobby." / Kilowatt: "It was ugly."
  - Kilowatt: "Sixty-forty, Saye. It was always supposed to be sixty-forty."
  - Saye: "Try to hit them, not the building."

When both are down, VEX takes the roof (see VEX, above).

Both drop a pickup when they go down and each raises `serverKill` with kind
"boss". What they drop, and the quest's reward, waits on the Shard's ending.

### The factions' troops

On the street everyone is drawn top down as a person (`src/body.lua`, 9 px
radius) in their faction's colours, with one thing each that makes their
role readable at a glance. All numbers here are starting points for tuning;
for scale, a Combine soldier has 60 health and drops 3 koins.

The two factions play differently on purpose:

| | Halcyon | The Static |
| --- | --- | --- |
| Style | Disciplined: formations, cover, procedure | Reckless: packs that rush, no cover, all noise |
| Colour | Grey, white helmets, a magenta visor strip | Dark mismatched clothes, chrome limbs, cyan cable tips |
| Brain | The Combine's (`a-man/combine.lua`) as it is: posts, squads, sweeps | A rusher: no posts, packs of 3-5 that close in and keep moving |
| Breach | Almost everything they field is tech: turrets, drones, cameras, cars | Mostly flesh and chrome: one breach target, the Brute's arm |
| Weak to | Flanking, breach, Static EMPs | Choke points, cover, Halcyon's shields |

So Halcyon fights are puzzles you can hack, and Static fights are brawls you
have to shoot your way through.

#### Halcyon

| Unit | Look | Health | Gun / attack | Behaviour |
| --- | --- | --- | --- | --- |
| **Officer** | Grey armour, white helmet, magenta visor strip | 60 | SMG or pistol (`bullet`) | Rank and file: posts and squads of 3, like the Combine. Calls in what they see. |
| **Enforcer** | Darker grey, a riot shield in front with a magenta edge | 120 | Shotgun (`bullet`) | Slow. The shield stops everything from in front; flank him or blow him up. Holds doorways and choke points. |
| **Marksman** | Dark helmet, long rifle | 40 | Rifle (`bullet`, hits hard) | Rooftops and catwalks. A thin magenta line shows his aim a second before he fires, like Saye's sightline but slower. |
| **Watcher drone** | A small flying disc with a magenta eye and a sight cone | 20 | None | Flies a patrol over walls. Seeing you sets off an alarm that calls the nearest squad. Breach it to blind it. |
| **Sting drone** | Smaller, faster | 20 | Light gun (`bullet`) | Flies in swarms of 3-4 in the tower and with Saye. |
| **Sentry turret** | A grey tripod with a magenta lens | 80 | Burst fire (`bullet`) | Fixed. Breach it and it fights for you for 15 s. |
| **Interceptor** | A grey sedan with a magenta and blue light bar | car | Rams; an officer leans out and shoots | The Drop and the Overpass. Tries to box you in and spin you out. Breach it parked and it stays dead. |

#### The Static

| Unit | Look | Health | Gun / attack | Behaviour |
| --- | --- | --- | --- | --- |
| **Ganger** | Dark clothes, cyan-tipped cable hair, a chrome forearm | 50 | Shotgun or pistol (`bullet`) | Packs of 3-5 that run straight at the nearest target, shooting as they go. |
| **Ripper** | Lean, with two chrome blades out from the forearms | 40 | Blades (`melee`) | Fast. Crouches for half a second, then lunges a long way (dodge it sideways). Goes for whoever is alone. |
| **Brute** | A small Kilowatt: huge, a giant chrome arm, a cyan reactor glow | 150 | Punch (`impact`), a short charge | Slow, tough, soaks fire for the pack. Breach his arm and it locks up and he swings at whoever is next to him (often his own side) for 4 s. |
| **Sparker** | Hooded, a belt of cyan-glowing EMP grenades | 40 | EMP grenade (`shock`) | Hangs back and lobs EMPs. An EMP knocks out drones, turrets and cars in its blast for 5 s, Halcyon's and yours alike. |
| **War-rig** | An armoured truck with a spiked chrome ram and a ganger on the back | car | Rams (`impact`); the ganger shoots | The Drop and the Overpass. Built to ram you off the road, and Halcyon's interceptors too. |

#### How they fight each other

While the factions are hostile (levels 1-2, see "Feud AI"), each picks its
target from the other faction as well as from players, the nearest it can
see. Their kits answer each other, so it pays to set them on each other:

- Sparkers' EMPs drop Halcyon's drones and turrets.
- Enforcers' shields stop a Static rush in a doorway.
- Rippers go round the shields and through the marksmen.
- War-rigs ram interceptors off the road.

On the Overpass (level 3) they only shoot each other when the other side
shoots first. From level 4 on they never do.

#### What they say

Same system as the Combine's radio (`a-man/radio.lua`): categories picked by
the host, a bubble over their heads, a sound per faction (a clipped radio
click for Halcyon, a distorted shout for the Static).

| Category | Halcyon | The Static |
| --- | --- | --- |
| `post` / `idle` | "Floor secure. Logging it." / "Code green, no visitors." | "Bored. Somebody start something." / "Who took my battery?" |
| `alert` (you) | "Unscheduled contractor, sector four." / "Visitor without a badge." | "COURIER! Get 'em!" / "There's the delivery!" |
| `alert` (the other side) | "Static in the lobby!" / "Gang activity, engage." | "Grey suits! Light 'em up!" / "Corp-meat at twelve!" |
| `down` | "Officer down. Filing it." / "We have a casualty." | "They got Ratchet!" / "Oh, that's gonna leave a mark." |
| `truce` (levels 3-4) | "Hold fire on the Static. Courier first." | "Easy, suit. Courier first, then you." |
| `breached` | "My drone's not responding." / "Turret's compromised!" | "Why's my ARM doing that?!" |

#### Who turns up where

| Level | Halcyon | The Static |
| --- | --- | --- |
| 1. The Drop | Interceptors, a few officers at roadblocks | War-rigs, gangers on foot at corners |
| 2. The Market | Officers in squads, enforcers in the market's gates, watcher drones | Packs of gangers, rippers, a sparker or two |
| 3. The Overpass | Interceptors, sting drones strafing, marksmen on the gantries | War-rigs (Kilowatt rides the first), gangers at the ambush |
| 4. Halcyon Tower | Everything: officers, enforcers, marksmen, watchers, stings, turrets | Gangers, brutes and sparkers breaking in from below |
| 5. The Roof | Saye's sting drones and turrets | Brutes coming up the stairs while Kilowatt fights |

Each drops koins when it goes down (officers and gangers 3, the heavier
ones more) and maybe a pickup, and every kill raises `serverKill`.

## The arc: the feud breaks down as you go

The two factions start out at war with each other and end up fighting side by
side against you. The game gets lonelier as the story does.

| # | Map | Play | Who's after you |
| --- | --- | --- | --- |
| 1 | **The Drop**: downtown, night, rain | Driving chase across town with the Shard | Both sides, separately, also fighting each other |
| 2 | **The Market**: neon stalls, crowded, on foot | Get through a three-way firefight | Both sides; you survive by pulling them into each other |
| 3 | **The Overpass**: elevated highway over the grey | Driving: war-rigs ram you, drones strafe | Both sides, starting to hold fire on each other. VEX "finds you a shortcut" straight into an ambush |
| 4 | **Halcyon Tower**: on foot, stealth and hacking | Breach cameras, turrets and doors, and climb | Halcyon inside, the Static breaking in; they ignore each other now |
| 5 | **The Roof**: the finale | Saye and Kilowatt fight together, as a tag-team boss | Then VEX locks the roof and turns the tower's turrets on you |

### 1. The Drop

The job on the board: "Courier wanted. No questions." Everyone arrives
downtown at night in the rain. The Shard is waiting in a vending machine. Once
someone has it, both factions come for it in cars and the level becomes a
chase across town to the exit. VEX boots up in the dash halfway through: her
intro screen.

Unlike City 17, the quest opens with driving rather than on foot.

### 2. The Market

A dense on-foot market of neon stalls in a grey concrete block. Both factions
catch up at once. They shoot at each other as much as at you, and the way
through is to pull one side into the other: lead Static gangers into a Halcyon
checkpoint and watch from cover.

### 3. The Overpass

An elevated highway out over the city. Static war-rigs ram you, and Halcyon
drones strafe from above. The factions start holding fire on each other here.
VEX finds you "a shortcut" that runs straight into an ambush where both sides
are waiting together: the first sign they are working it out.

### 4. Halcyon Tower

On foot, mostly stealth and hacking, climbing floor by floor. Cameras,
turrets and locked doors are all breach targets. Halcyon guards the inside,
and the Static is breaking in from below. They no longer shoot each other;
they only want you.

### 5. The Roof

Saye and Kilowatt fight together as a tag-team boss: Saye at range with
drones and turrets, Kilowatt up close with his bulk. When they are down, VEX
locks the roof and turns the tower's turrets on everyone. The last phase is
breaching VEX out of the tower's systems while the turrets fire. You beat
her, but she escapes into the net with a parting line ("Nothing personal,
courier."), which sets up the sequel.

## Mechanics

### Feud AI

Two enemy factions with a hostility between them that changes per level:

| Level | Halcyon vs. the Static |
| --- | --- |
| 1, 2 | Fully hostile: they shoot each other on sight |
| 3 | Sometimes hold fire |
| 4 | Share targets: ignore each other, hunt you |
| 5 | One team, the bosses fighting together |

A-Man's Combine is the only enemy side on its maps, so this is new. The
soldiers' brain (`a-man/combine.lua`, with D-Day's sight cones) is the place
to start; what it needs is a faction on each soldier and a way to choose
targets from the other faction as well as from players.

### Breach (the hacking mini-game)

On foot, press F (`actionTaken`) at a terminal, turret, camera or parked car to
get a small hex-code grid: pick a given sequence against a timer. On success:

- a turret switches to your side for a while
- a camera goes blind
- a door opens
- a car is bricked (stops dead)

The world does not pause while you breach, so in co-op someone covers the
hacker. As always, the server decides whether a breach succeeds; the client
sends only its picks.

### VEX's chatter

Like the Combine's radio (`a-man/radio.lua`): lines in a bubble with a
sound, plus a burst of HUD glitch on her big lines. Her lines sound helpful
and turn out to be lies, and some get called back later ("Take the left exit,
it's quiet" -> the ambush). Her intro screen works like A-Man's
(`a-man/screen.lua`): her portrait and a line picked by index, glitching
where his jumps.

## Look

- Grey concrete, constant rain, wet streets that catch the neon.
- Neon only in faction colours (magenta for Halcyon, cyan for the Static),
  plus VEX's green on the HUD. Anywhere you see colour, there's someone who
  wants you dead.
- Pun shop signs: NOODLZ, CHROME 4 LESS, RIPPERDOC, NO REFUNDS.
- Each map gets its own theme music, as A-Man's do.

## Open questions

- **The Shard's ending.** Keep it, broadcast it to the city, or something else.
  It decides the last screen's line, and maybe the reward.
- **The reward.** One idea is the Shard as a legendary ability: one use per
  fight turns two enemies on each other, a small feud of your own. Whatever it
  is, it is equipment, so it has tiers (`tierStats`, read through
  `Tiers.apply`).
- **The sequel.** VEX gets away; where she goes is for that quest line.

## Next steps

1. Character design: VEX, Saye, Kilowatt and the factions' troops (done).
2. Map design for the five levels (city-map builds and draws them).
3. Feud AI and breach as their own pieces, since later quests can use them
   too.
