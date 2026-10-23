-- Quill & Hearth: the in-game template writer. Writes a journal entry with no AI at all, in the
-- character's voice (from onboarding), from the same digest the AI prompt uses.
-- Variants are picked with a seed from the rest, so the same night always reads the same.
local _, QH = ...

local T = {}
QH.Templates = T

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function Rng(seed)
    local state = (seed or 1) % 2147483647
    if state <= 0 then state = state + 2147483646 end
    return function(n)
        state = (state * 16807) % 2147483647
        return (state % n) + 1
    end
end

local function Fill(template, vars)
    return (template:gsub("{(%w+)}", function(key) return vars[key] or "" end))
end

local function Join(list)
    if #list == 0 then return "" end
    if #list == 1 then return list[1] end
    return table.concat(list, ", ", 1, #list - 1) .. " and " .. list[#list]
end

local function Capitalize(s)
    return (s:gsub("^%l", string.upper))
end

local VOICES = { Plain = true, Formal = true, Poetic = true, Terse = true }

local function VoiceOf(profile)
    local v = profile and profile.traits and profile.traits.voice
    return VOICES[v] and v or "Plain"
end

---------------------------------------------------------------------------
-- Phrase banks: [voice] = { variants... }. {placeholders} are filled per moment.
---------------------------------------------------------------------------
local B = {}

B.openRested = {
    Plain = { "I'm writing this at {place}, glad of a roof and a bed.", "A quiet corner at {place} and a little ink. Time to set down what happened." },
    Formal = { "I set down these lines at {place}, where I have taken lodging for the night.", "From {place}, I record the events of recent days." },
    Poetic = { "Lamplight flickers across the page here at {place}, and the day's dust is finally settling.", "The common room at {place} hums softly around me as I write." },
    Terse = { "{place}. A bed. Ink.", "Resting at {place}." },
}
B.openCampfire = {
    Plain = { "I've made camp near {place} and the fire is warm enough to write by.", "Sitting by a campfire near {place}, I finally have a moment to write." },
    Formal = { "I write by the light of a campfire near {place}.", "Encamped near {place}, I take the opportunity to record the day." },
    Poetic = { "Sparks climb into the dark above my little fire near {place}, and the page glows orange.", "The fire near {place} crackles like an old friend telling stories." },
    Terse = { "Camp near {place}. Fire's lit.", "Campfire. {place}. Writing." },
}
B.nextDay = {
    Plain = { "The next day, ", "The following morning, " },
    Formal = { "On the following day, ", "When the next day dawned, " },
    Poetic = { "When dawn came again, ", "With the new morning, " },
    Terse = { "Next day: ", "Morning. " },
}
B.daysLater = {
    Plain = { "Some days later, ", "A few days on, " },
    Formal = { "Several days thereafter, ", "Some days later, " },
    Poetic = { "Days slipped past, and then ", "Many sunrises later, " },
    Terse = { "Days later: ", "Later. " },
}
B.voyage = {
    Plain = { "I left {from} behind and spent {days} days travelling to {continent}, landing in {zone}.", "The crossing to {continent} took {days} long days before I reached {zone}." },
    Formal = { "I departed {from} and, after a passage of some {days} days, arrived upon the shores of {continent} at {zone}.", "A voyage of {days} days carried me from {from} to {zone}, in {continent}." },
    Poetic = { "For {days} days the sea rocked me from {from} toward {continent}, until {zone} rose out of the haze.", "{continent} was only a rumour on the horizon for {days} days; then {zone} welcomed me ashore." },
    Terse = { "{days} days of travel. {from} to {zone}, {continent}.", "Crossed to {continent}. {days} days. Landed in {zone}." },
}
B.firstVisit = {
    Plain = { "I set foot in {zone} for the first time.", "{zone} was new to me." },
    Formal = { "I entered {zone}, a land I had not visited before.", "For the first time, my road led into {zone}." },
    Poetic = { "{zone} opened before me, strange and new.", "I walked into {zone} for the first time, every path unfamiliar." },
    Terse = { "First time in {zone}.", "New ground: {zone}." },
}
B.flight = {
    Plain = { "I caught a flight to {dest}.", "A ride on the wind took me to {dest}." },
    Formal = { "I took passage by air to {dest}.", "A flight carried me swiftly to {dest}." },
    Poetic = { "I flew to {dest}, the land unrolling beneath me like a map.", "The wind bore me to {dest}, high above the treetops." },
    Terse = { "Flew to {dest}.", "Flight to {dest}." },
}
B.hearth = {
    Plain = { "When the work was done, I used my hearthstone to return to {home}.", "I headed home to {home} by hearthstone." },
    Formal = { "I returned by hearthstone to {home}.", "My hearthstone carried me back to {home}." },
    Poetic = { "The hearthstone's glow pulled me home to {home} in a heartbeat.", "A flash of light, and {home} was around me again." },
    Terse = { "Hearthed to {home}.", "Back to {home}." },
}
B.bind = {
    Plain = { "I've decided to call {home} home for now.", "{home} is where I'll lay my head from now on." },
    Formal = { "I have made {home} my place of residence.", "I have taken up lodging at {home} for the foreseeable future." },
    Poetic = { "{home} will be my hearth now, for as long as the road allows.", "I've tied my heart, for a while, to {home}." },
    Terse = { "New home: {home}.", "Staying at {home} now." },
}
B.taskDone = {
    Plain = { "I finished the matter of {title}.", "I saw {title} through to the end.", "{title} is done." },
    Formal = { "I brought the matter of {title} to its conclusion.", "I completed the task known as {title}.", "The affair of {title} is concluded." },
    Poetic = { "{title}: that thread is woven to its end.", "I closed the chapter of {title}.", "{title} lies behind me now." },
    Terse = { "{title}. Done.", "Finished {title}.", "{title}: handled." },
}
B.taskAccepted = {
    Plain = { "I agreed to help with {title}. It still lies ahead of me.", "Someone asked for my help with {title}; I said yes." },
    Formal = { "I have accepted responsibility for {title}, though it remains unfinished.", "I pledged my aid in the matter of {title}." },
    Poetic = { "A new burden: {title}. I carry it into tomorrow.", "{title} waits for me, like a road not yet walked." },
    Terse = { "Took on {title}. Not done yet.", "New task: {title}." },
}
B.taskStory = {
    Plain = { "It started with this: {story}", "The gist of it: {story}" },
    Formal = { "The circumstances were these: {story}", "As it was explained to me: {story}" },
    Poetic = { "The tale, as it was told to me: {story}", "Its story stays with me: {story}" },
    Terse = { "{story}", "Short version: {story}" },
}
B.fear = {
    Plain = { "Of all things, it had to involve {hook}. I did it anyway.", "{Hook}. Of course it was {hook}. My hands shook, but I didn't turn back." },
    Formal = { "I confess the involvement of {hook} tested my composure, yet I did not falter.", "That {hook} should be involved was a trial I had not wished for, but I endured it." },
    Poetic = { "{Hook}, the very shape of my nightmares, and still I walked toward it.", "Fear of {hook} gnawed at me with every step, and I stepped anyway." },
    Terse = { "{Hook}. Hate them. Did it anyway.", "{Hook} again. Didn't run." },
}
B.death = {
    Plain = { "I was struck down near {place} and woke at a spirit healer's side. I'm still shaken.", "I nearly didn't make it out of {place}; I came to at a spirit healer, bruised in more than body." },
    Formal = { "I fell near {place}, and only the grace of a spirit healer returned me to the world.", "I was overcome near {place}; I awoke in the care of a spirit healer." },
    Poetic = { "Darkness took me near {place}, and for a moment there was nothing. Then the spirit healer's light.", "I fell near {place}, and the world went grey and silent before it let me back." },
    Terse = { "Died near {place}. Spirit healer. Back on my feet.", "Struck down at {place}. Woke at a spirit healer." },
}
B.deathBy = {
    Plain = { "{killer} struck me down near {place}; I woke at a spirit healer's side, still shaken.", "I lost a fight with {killer} near {place} and came to at a spirit healer." },
    Formal = { "I fell to {killer} near {place}, and only a spirit healer returned me to the world.", "Overcome by {killer} near {place}, I awoke in the care of a spirit healer." },
    Poetic = { "{killer} brought me down near {place}, and the world went grey before the spirit healer's light called me back.", "I fell before {killer} near {place}; for a breath there was only silence." },
    Terse = { "{killer} got me near {place}. Spirit healer. Still breathing.", "Fell to {killer} at {place}. Back on my feet." },
}
B.foe = {
    Plain = { "I brought down {foe} near {place}. That was no small fight.", "I crossed paths with {foe} near {place} and walked away the victor." },
    Formal = { "I engaged and defeated {foe} near {place}.", "Near {place}, I prevailed against {foe}." },
    Poetic = { "{foe} stood in my way near {place}, and fell before the dust settled.", "A fierce struggle near {place}, and {foe} is no more." },
    Terse = { "Killed {foe} near {place}. Tough fight.", "{foe} at {place}. Down." },
}
B.spellLearned = {
    Plain = { "I've learned a new art: {spell}. It already feels natural.", "With some training, I've mastered the basics of {spell}." },
    Formal = { "I have been instructed in {spell}, a discipline I intend to put to use.", "My training has yielded a new capability: {spell}." },
    Poetic = { "Something new answers when I reach for it now: {spell}.", "{spell} — a new note in the song of what I can do." },
    Terse = { "Learned {spell}.", "New trick: {spell}." },
}
B.moneyMilestone = {
    Plain = { "I counted my pouch tonight and smiled: {milestone} of my own.", "My coin pouch is heavier than it's ever been — {milestone}." },
    Formal = { "My savings have reached a modest milestone: {milestone}.", "Through steady effort, I have accumulated {milestone}." },
    Poetic = { "Coins clink softly in my pouch tonight: {milestone}, earned the hard way.", "For the first time, I hold {milestone} in my own hand." },
    Terse = { "Saved up {milestone}.", "Pouch holds {milestone} now." },
}
B.moneySpent = {
    Plain = { "Training and supplies took {spent} out of my pouch, leaving me with {left}.", "I parted with {spent} today and have only {left} to my name." },
    Formal = { "Necessary expenses required {spent}, leaving me with {left}.", "After disbursing {spent} on training and provisions, {left} remains." },
    Poetic = { "{spent} vanished into eager hands today; my pouch is light again, down to {left}.", "Coin goes faster than it comes: {spent} spent, {left} left." },
    Terse = { "Spent {spent}. Down to {left}.", "Broke again. {left} left." },
}
B.level = {
    Plain = { "I feel stronger than I did a few days ago.", "Something has changed in me. I'm more capable than before." },
    Formal = { "I find my abilities much improved of late.", "My skills have grown considerably." },
    Poetic = { "There is a new strength in my arms and a new certainty in my step.", "I am not who I was when this road began." },
    Terse = { "Stronger now.", "Getting better at this." },
}
B.dungeon = {
    Plain = { "We went into {instance}{with}.", "{Instance} was dark and dangerous, and we went in anyway{with}." },
    Formal = { "We ventured into {instance}{with}.", "I entered {instance}{with}." },
    Poetic = { "{Instance} swallowed us whole{with}, and somehow spat us back out.", "Into the depths of {instance} we went{with}." },
    Terse = { "{Instance}{with}. Went in.", "Entered {instance}{with}." },
}
B.minor = {
    Plain = { "I also saw to {list}.", "Besides that, there was {list}." },
    Formal = { "I further attended to {list}.", "Other matters included {list}." },
    Poetic = { "Smaller threads ran through the days as well: {list}.", "Between it all: {list}." },
    Terse = { "Also: {list}.", "Plus {list}." },
}
B.errands = {
    Plain = { "The rest of the time went to small jobs around {zones}.", "Plenty of odd jobs around {zones} filled the gaps." },
    Formal = { "The remainder of my time was spent on minor errands about {zones}.", "Various small duties around {zones} occupied the rest." },
    Poetic = { "The rest dissolved into small errands around {zones}, the kind no one sings about.", "Little tasks around {zones} filled the hours between." },
    Terse = { "Odd jobs around {zones}.", "Errands. {zones}." },
}
B.noteIntro = {
    Plain = { "One more thing I want to remember: ", "Something I keep thinking about: " },
    Formal = { "I wish to record the following: ", "A private reflection: " },
    Poetic = { "And this, before the ink dries: ", "A thought I cannot shake: " },
    Terse = { "Note: ", "Remember: " },
}
B.quiet = {
    Plain = { "Not much happened, honestly. A quiet stretch.", "A quiet few days, and I'm grateful for it." },
    Formal = { "These days passed without remarkable incident.", "Little of consequence occurred." },
    Poetic = { "The days slipped by like water, leaving little behind.", "A stillness lay over these days." },
    Terse = { "Quiet. Nothing much.", "Uneventful." },
}
B.time = {
    Plain = { "It's {time} as I write.", "Writing this {time}." },
    Formal = { "I write {time}.", "The hour: {time}." },
    Poetic = { "It is {time}, and the world has gone soft and quiet.", "I write {time}, while the world holds its breath." },
    Terse = { "{Time}.", "{Time}. Tired." },
}
B.giver = {
    Plain = { "{giver} had asked for my help with it.", "It was {giver} who asked." },
    Formal = { "I undertook it at the request of {giver}.", "{giver} had entrusted it to me." },
    Poetic = { "{giver} had pressed the matter into my hands.", "It began with {giver}'s request." },
    Terse = { "For {giver}.", "{giver} asked." },
}
B.giverAgain = {
    Plain = { "{giver} again. We're getting to know each other.", "Once more it was {giver} who asked; I'm becoming a familiar face to them." },
    Formal = { "Once again, {giver} sought my assistance.", "{giver}, whom I have aided before, called upon me again." },
    Poetic = { "{giver} again, a familiar face on an unfamiliar road.", "Our paths crossed once more, {giver} and I." },
    Terse = { "{giver} again.", "For {giver}. Again." },
}
B.loot = {
    Plain = { "I came away with something special: {item}.", "Among the day's spoils was {item}. I keep looking at it." },
    Formal = { "I acquired a notable item: {item}.", "Fortune granted me {item}." },
    Poetic = { "{item} came into my keeping, and it feels like a promise.", "I found {item}, and for a moment the road felt kinder." },
    Terse = { "Found {item}. Good.", "New gear: {item}." },
}
B.reputation = {
    Plain = { "{faction} seem to trust me more now. I'm {standing} with them, they say.", "I've earned some standing with {faction}: {standing}, no less." },
    Formal = { "My standing with {faction} has risen to {standing}.", "{faction} now regard me as {standing}." },
    Poetic = { "{faction} look at me differently now; I am {standing} in their eyes.", "Doors open a little wider among {faction}. {Standing}, they call me." },
    Terse = { "{faction}: {standing} now.", "{Standing} with {faction}." },
}
B.skill = {
    Plain = { "My {skill} keeps getting better; I'd put myself at {rank} now.", "Practice is paying off. My {skill} has come a long way." },
    Formal = { "My proficiency in {skill} has reached {rank}.", "I have made steady progress in {skill}." },
    Poetic = { "My hands are learning {skill}, one patient lesson at a time.", "{Skill} comes easier to me now, like a song I almost know." },
    Terse = { "{Skill}: {rank}.", "Better at {skill}." },
}
B.achievement = {
    Plain = { "I managed something I'm proud of: {achievement}.", "A small triumph worth writing down: {achievement}." },
    Formal = { "I count among my accomplishments: {achievement}.", "An accomplishment worth recording: {achievement}." },
    Poetic = { "{achievement}. Something to tell the fire about one day.", "I did it: {achievement}." },
    Terse = { "Done: {achievement}.", "{achievement}. Proud." },
}
B.camp = {
    Plain = { "I stopped by a campfire for a while and just sat.", "There was a campfire on the road, and I let myself rest by it." },
    Formal = { "I paused at a campfire to rest and gather my thoughts.", "A campfire offered a brief respite." },
    Poetic = { "I sat by a campfire and watched the sparks climb, and for once I thought of nothing.", "A fire on the roadside, a little warmth, a little peace." },
    Terse = { "Sat by a fire. Rested.", "Campfire. Short rest." },
}
B.reflection = {
    Plain = { "Looking back, I'm not who I was when I set out. I've grown, and I can feel it.", "Some days I barely recognize the person who started this journey." },
    Formal = { "In reflection, I am much changed since my journey began.", "I am not the same person who first set out, and I find I do not regret it." },
    Poetic = { "When I think of who I was at the start, it feels like a stranger's story, and yet it's mine.", "The road has carved me into someone new." },
    Terse = { "I've changed. Good.", "Not who I was. Stronger." },
}
B.flavor = {
    hearth_soup = {
        Plain = { "I can smell a hearty soup while writing this journal; I should go check it out as soon as I'm done." },
        Formal = { "The aroma of a hearty soup drifts over as I write; I shall inquire after a bowl once this page is finished." },
        Poetic = { "The rich scent of a simmering soup curls around my table as I write, calling me away from the ink." },
        Terse = { "Smell hearty soup while writing. Going to get some next." },
    },
    hearth_candle = {
        Plain = { "The candle on my table keeps sputtering and nearly dripping wax onto the page." },
        Formal = { "My table's tallow candle sputters unevenly, threatening to spot this page with wax." },
        Poetic = { "A restless candle gutters beside my hand, weeping warm wax near the margin." },
        Terse = { "Candle's sputtering. Almost dripped wax on the page." },
    },
    hearth_bard = {
        Plain = { "Someone across the room has been tuning an instrument with one stubbornly flat string this whole time." },
        Formal = { "A musician in the room has spent the evening wrestling with an obstinately flat string." },
        Poetic = { "Across the room, a minstrel plucks at a single flat string, over and over, like a question without an answer." },
        Terse = { "Someone's tuning a lute nearby. One string's still flat." },
    },
    hearth_patrons = {
        Plain = { "Two folks at the next table have been arguing in hushed voices over a crumpled map all evening." },
        Formal = { "At the neighbouring table, two patrons remain locked in a hushed dispute over a worn map." },
        Poetic = { "Whispers drift from the next table, where two strangers lean over a creased map like conspirators." },
        Terse = { "Two people at the next table arguing over a map." },
    },
    hearth_boots = {
        Plain = { "My boots are propped near the fire, still caked with mud from {zone}." },
        Formal = { "My boots rest near the hearth, still bearing the dust and mire of {zone}." },
        Poetic = { "By the warmth, my boots slowly shed the stubborn mud of {zone}." },
        Terse = { "Boots drying by the fire. Still muddy from {zone}." },
    },
    camp_ember = {
        Plain = { "A damp branch in the fire just hissed and popped an ember right onto the corner of this page." },
        Formal = { "A damp bough in the fire popped just now, casting a stray ember onto the corner of my page." },
        Poetic = { "The fire hissed and tossed a tiny, glowing ember onto the corner of my page — a little scar of ash." },
        Terse = { "Fire popped an ember onto the page. Brushed it off." },
    },
    camp_rustle = {
        Plain = { "Something rustled in the brush just past the firelight and had me reaching for my weapon, though it was only a critter." },
        Formal = { "A sudden rustling beyond the firelight caused me to reach for my weapon, though it proved to be harmless wildlife." },
        Poetic = { "The dark beyond the firelight rustled and made my hand jump to my weapon, only for a small shadow to scamper away." },
        Terse = { "Noise in the brush by camp. Reached for my weapon. Just a critter." },
    },
    camp_tea = {
        Plain = { "I've got a tin cup simmering on the stones beside the fire while I write." },
        Formal = { "A modest cup simmers upon the stones beside the fire as I set down these thoughts." },
        Poetic = { "A dented cup steams quietly on the hearth-stones beside the fire as my pen moves." },
        Terse = { "Tin cup boiling by the coals while I write." },
    },
    camp_stars = {
        Plain = { "Looking up from the page, the smoke parted and left a remarkably clear view of the stars above {zone}." },
        Formal = { "Through a break in the woodsmoke, the night sky above {zone} is remarkably clear tonight." },
        Poetic = { "The woodsmoke parted just now, unveiling a cold, brilliant river of stars above {zone}." },
        Terse = { "Clear stars above {zone} tonight." },
    },
    camp_owl = {
        Plain = { "A night bird has been calling from the dark around {place} every few minutes while I write." },
        Formal = { "A night bird has been calling at intervals from the darkness beyond {place}." },
        Poetic = { "Out in the dark around {place}, a night bird keeps calling, lonely and clear." },
        Terse = { "Owl calling in the dark near {place}." },
    },
    out_watch = {
        Plain = { "The night watch just walked past with clinking lanterns and gave me a quiet nod." },
        Formal = { "The night watch passed by moments ago, their lanterns clinking softly as they offered a brief nod." },
        Poetic = { "Lanterns clinked as the night watch drifted past, leaving a brief nod and a pool of swaying light." },
        Terse = { "Night watch walked past. Nodded." },
    },
    out_vendor = {
        Plain = { "A vendor packing up nearby offered me the last loaf of bread for a couple of copper." },
        Formal = { "A merchant closing their stall for the evening offered me their last loaf for a few copper coins." },
        Poetic = { "A weary vendor folding up their stall sold me the day's last warm loaf for a pair of coppers." },
        Terse = { "Vendor packing up sold me the last loaf cheap." },
    },
    out_breeze = {
        Plain = { "A cool breeze at {place} keeps trying to turn the pages of this journal for me." },
        Formal = { "A cool evening breeze at {place} persistently stirs the pages as I write." },
        Poetic = { "The evening breeze at {place} keeps tugging at the corners of this page, impatient for me to finish." },
        Terse = { "Wind keeps flipping the page." },
    },
    combat_miss = {
        Plain = { "At one point in {zone}, my {ability} missed and the beast charged right at me — I had to dodge aside and steady myself to try again." },
        Formal = { "During an engagement in {zone}, my {ability} went wide as the creature charged; I was forced to evade its lunge and regain my focus." },
        Poetic = { "Once in {zone}, my {ability} went astray and the beast lunged into the gap — I barely twisted clear before gathering myself again." },
        Terse = { "{ability} missed in {zone}. Foe charged. Dodged and reset." },
    },
    combat_footing = {
        Plain = { "My footing slipped on loose dirt during a fight in {zone}, and I took a glancing hit before turning things around with {ability}." },
        Formal = { "Loose ground betrayed my footing during a skirmish in {zone}, costing me a glancing blow before I answered with {ability}." },
        Poetic = { "The earth gave way beneath my heel in {zone}; I took a bruising graze before answering with {ability}." },
        Terse = { "Slipped mid-fight in {zone}. Took a hit. Answered with {ability}." },
    },
    combat_ambush = {
        Plain = { "Something lunged out of the brush in {zone} when my guard was down, forcing a messy, point-blank {ability}." },
        Formal = { "An ambush from the undergrowth in {zone} caught me off guard and required an immediate {ability} at close quarters." },
        Poetic = { "Teeth and shadow burst from the brush in {zone} while my thoughts were elsewhere; only an instinctive {ability} kept me whole." },
        Terse = { "Ambushed in {zone}. Point-blank {ability} saved me." },
    },
    combat_exhaust = {
        Plain = { "After leaning on {ability} so many times in {zone}, my arms were aching by the last fight." },
        Formal = { "Repeated use of {ability} throughout {zone} left me noticeably fatigued by the final engagement." },
        Poetic = { "Calling upon {ability} again and again in {zone} left a deep, hollow ache in my bones by nightfall." },
        Terse = { "Used {ability} all day in {zone}. Worn out." },
    },
    combat_narrow = {
        Plain = { "One fight in {zone} went closer than I'd like to admit — a timely {ability} ended it just as my breath was giving out." },
        Formal = { "One encounter in {zone} proved narrower than expected; only a well-timed {ability} decided it in my favour." },
        Poetic = { "One battle in {zone} balanced on a knife's edge until a final, desperate {ability} tipped the scales." },
        Terse = { "Close fight in {zone}. {ability} finished it just in time." },
    },
    combat_gear = {
        Plain = { "Even with {ability}, a hard blow during a scrap in {zone} left a fresh dent in my gear that I had to patch up afterward." },
        Formal = { "Despite relying upon {ability}, a heavy strike in {zone} left my equipment damaged, requiring repairs before I could press on." },
        Poetic = { "Even with {ability} at my call, a fierce blow in {zone} left its mark upon my gear — another scar to mend by firelight." },
        Terse = { "Took a hard hit in {zone} before {ability} ended it. Had to patch my gear." },
    },
    town_drunk = {
        Plain = { "While heading back toward {town}, I crossed paths with a drunken local who asked me for coins; I ignored them and kept walking." },
        Formal = { "Upon returning toward {town}, an inebriated local accosted me for coin; I declined to engage and continued on my way." },
        Poetic = { "On the road back to {town}, a drunken soul stumbled into my path begging for coin; I left them to their cups and walked on." },
        Terse = { "Drunk near {town} asked for coin. Ignored them." },
    },
    town_peddler = {
        Plain = { "Near {town}, a fast-talking peddler tried to sell me a 'lucky charm' for an absurd price. I passed." },
        Formal = { "Near {town}, an enterprising peddler attempted to sell me a dubious talisman at an exorbitant sum." },
        Poetic = { "By {town}, a silver-tongued peddler offered me painted luck for real coin; I kept my purse closed." },
        Terse = { "Peddler near {town} pushing fake charms. Kept walking." },
    },
    town_guards = {
        Plain = { "Guards along the road near {town} stopped me briefly to ask if I'd seen any trouble out in {zone}." },
        Formal = { "Sentries near {town} halted me briefly to inquire about conditions along the roads of {zone}." },
        Poetic = { "Watchmen near {town} stopped me to ask what news the roads of {zone} carried today." },
        Terse = { "Guards near {town} asked about the roads in {zone}." },
    },
    town_lost = {
        Plain = { "A confused traveler near {town} stopped me to ask for directions through {zone}; I pointed them the right way." },
        Formal = { "Near {town}, a wayfarer sought directions through {zone}, which I provided as best I could." },
        Poetic = { "A lost traveler near {town} asked me the way through {zone}; I pointed them down the safer road." },
        Terse = { "Lost traveler near {town}. Pointed them the right way." },
    },
    town_courier = {
        Plain = { "A mud-splattered courier on a lathered mount nearly ran me down on the road into {town}." },
        Formal = { "A haste-driven courier on a lathered mount nearly collided with me on the approach to {town}." },
        Poetic = { "Hooves thundered past on the road to {town} as a mud-streaked rider nearly swept me into the ditch." },
        Terse = { "Courier on a fast mount almost ran me over near {town}." },
    },
    town_children = {
        Plain = { "Passing near {town}, a few local kids stopped their game to stare at my travel-worn gear." },
        Formal = { "As I passed near {town}, several local children paused to stare curiously at my travel-stained equipment." },
        Poetic = { "Near {town}, a handful of children watched me pass with wide, curious eyes." },
        Terse = { "Kids near {town} stared at my dusty gear as I passed." },
    },
    road_wind = {
        Plain = { "A sudden gust of wind in {zone} blew my hat right off, and I had to chase it down and pick it back up." },
        Formal = { "A sharp gust of wind in {zone} carried off my headgear, obliging me to pause and retrieve it." },
        Poetic = { "A mischievous gust in {zone} snatched at my hat and sent me chasing it down the dusty path." },
        Terse = { "Wind blew my hat off in {zone}. Had to pick it back up." },
    },
    road_strap = {
        Plain = { "A strap on my pack snapped halfway through {zone}, spilling my things into the dirt until I knotted it back together." },
        Formal = { "A strap upon my pack gave way in {zone}, forcing me to halt and repair it by the roadside." },
        Poetic = { "Halfway through {zone}, a worn pack-strap finally surrendered, scattering my gear across the dust until I tied it fast." },
        Terse = { "Pack strap snapped in {zone}. Knotted it back together." },
    },
    road_stream = {
        Plain = { "I stopped by a cold stream in {zone} to wash the road dust from my face and refill my waterskin." },
        Formal = { "I paused beside a clear stream in {zone} to wash the dust from my face and replenish my water." },
        Poetic = { "A cold stream in {zone} let me wash the road from my face and fill my waterskin with clear water." },
        Terse = { "Stopped at a stream in {zone}. Washed up, refilled water." },
    },
    road_pebble = {
        Plain = { "I walked a good mile through {zone} with a sharp pebble in my boot before finally sitting on a rock to shake it out." },
        Formal = { "A persistent stone in my boot plagued my march through {zone} until I halted to remove it." },
        Poetic = { "A single stubborn pebble in my boot turned a mile of {zone} into a quiet penance before I finally shook it free." },
        Terse = { "Pebble in my boot in {zone}. Stopped and shook it out." },
    },
    road_shower = {
        Plain = { "A brief, unexpected rain shower in {zone} soaked my shoulders before the sky cleared up again." },
        Formal = { "A sudden passing shower in {zone} drenched my cloak before the clouds parted once more." },
        Poetic = { "A sudden curtain of rain swept across {zone}, dampening my shoulders before vanishing as quickly as it came." },
        Terse = { "Brief rain in {zone}. Soaked my cloak, then cleared." },
    },
    road_trinket = {
        Plain = { "Beside the path in {zone}, I spotted a strangely carved little stone half-buried in the dirt and pocketed it." },
        Formal = { "Along the path in {zone}, I noticed a curiously carved stone half-buried in the earth and kept it." },
        Poetic = { "Half-hidden in the dust of {zone}, a small carved stone caught my eye; it sits in my pocket now." },
        Terse = { "Found a carved stone on the path in {zone}. Kept it." },
    },
    road_shortcut = {
        Plain = { "What looked like a shortcut in {zone} turned into a steep scramble through tangled brambles." },
        Formal = { "An apparent shortcut in {zone} proved ill-advised, leading me through a steep thicket of brambles." },
        Poetic = { "A promising side-path in {zone} betrayed me into a steep tangle of thorns and loose stone." },
        Terse = { "Bad shortcut in {zone}. Ended up in brambles." },
    },
    road_wildlife = {
        Plain = { "A startled critter bolted across the path right in front of me in {zone} and nearly gave me a heart attack." },
        Formal = { "A startled creature bolted across my path in {zone}, briefly catching me off guard in the quiet." },
        Poetic = { "Out of the hush of {zone}, a startled creature bolted across my boots and set my heart racing." },
        Terse = { "Critter bolted across the path in {zone}. Startled me." },
    },
}
-- Closings by the mood chosen when resting (take priority over temperament).
B.moodClose = {
    Weary = { "I'm so tired. Sleep, now.", "Every bone aches. Tomorrow can wait." },
    Triumphant = { "What a day. I'll sleep well tonight.", "I did well. I'll let myself be proud of that." },
    Troubled = { "Something about all this sits wrong with me.", "I can't shake this unease." },
    Grieving = { "It hurts more than I'll admit to anyone but this page.", "Some losses don't fit into words." },
    Hopeful = { "Tomorrow feels full of promise.", "For the first time in a while, I'm looking forward." },
    Content = { "A good day. I'm content.", "Warm, fed, and at peace. That's enough." },
}
-- Closings by temperament.
B.close = {
    Stoic = { "Tomorrow there will be more to do. I'll do it.", "Rest now. The road waits." },
    Cheerful = { "Tomorrow is bound to bring something good. It usually does!", "All in all, not a bad few days at all." },
    Brooding = { "Sleep won't come easily tonight.", "I wonder what all of this is leading to." },
    ["Hot-headed"] = { "Let tomorrow bring whatever it likes. I'll be ready.", "If trouble comes looking, it'll find me waiting." },
    Gentle = { "I hope everyone I met today sleeps safe tonight.", "May tomorrow be kinder to us all." },
    default = { "Enough for tonight.", "The candle's burning low. Enough for now." },
}
B.title = {
    task = { "{title}", "On {title}", "The Matter of {title}" },
    voyage = { "Across to {continent}", "A New Shore", "The Long Crossing" },
    death = { "A Close Call", "Back from the Brink", "Struck Down" },
    dungeon = { "Into {instance}", "The Depths of {instance}" },
    note = { "Thoughts by Firelight", "Things Worth Remembering" },
    quiet = { "Quiet Days in {zone}", "Day {day}", "A Few Days in {zone}" },
}

---------------------------------------------------------------------------
-- Writer
---------------------------------------------------------------------------
--- Write { title, body } for a digest. Told in the order things happened, which reads most
--- naturally for short template prose (the AI prompt groups by storyline instead).
function T.Write(digest, profile, opts)
    opts = opts or {}
    local voice = VoiceOf(profile)
    local temperament = profile and profile.traits and profile.traits.temperament
    local pick = Rng(digest.lastRest.seq * 7919 + digest.startDay)
    local function say(bank, vars)
        local variants = bank[voice] or bank.Plain
        return Fill(variants[pick(#variants)], vars or {})
    end

    local paragraphs, current = {}, {}
    local currentDay = digest.startDay
    local function flush()
        if #current > 0 then
            table.insert(paragraphs, table.concat(current, " "))
            current = {}
        end
    end
    --- Add a sentence; a new day starts a new paragraph with a time transition.
    local function sentence(s, day, transitionIncluded)
        if day and day > currentDay then
            flush()
            if not transitionIncluded then
                local bank = (day - currentDay > 1) and B.daysLater or B.nextDay
                s = say(bank) .. (s:gsub("^%u", string.lower))
            end
            currentDay = day
        elseif #current >= 4 then
            flush()
        end
        table.insert(current, s)
    end
    local function plural(word)
        return word:find("s$") and word or (word:find("y$") and word:gsub("y$", "ies") or word .. "s")
    end

    -- Opening
    local restPlace = digest.lastRest.subzone or digest.lastRest.zone or "the road"
    local opening = say(digest.restKind == "campfire" and B.openCampfire or B.openRested, { place = restPlace })
    if digest.timeOfDay then
        opening = opening .. " " .. say(B.time, { time = digest.timeOfDay, Time = Capitalize(digest.timeOfDay) })
    end
    table.insert(paragraphs, opening)

    -- One timeline of journey beats and story moments, in the order they happened.
    local timeline = {}
    for _, j in ipairs(digest.journey) do
        if j.event then table.insert(timeline, { seq = j.event.seq, day = j.day, journey = j.event }) end
    end
    local SPECIFIC = { loot = true, reputation = true, skill = true, achievement = true, camp = true,
        foe = true, spell_learned = true, money = true }
    local notes, minors = {}, {}
    local titleKind, titleVars
    for _, thread in ipairs(digest.threads) do
        for _, m in ipairs(thread.moments) do
            if m.note then
                table.insert(notes, m)
            elseif m.importance == "KEY" or SPECIFIC[m.type] then
                table.insert(timeline, { seq = m.seq or 0, day = m.day, moment = m })
            elseif m.title then
                table.insert(minors, m.giver and (m.title .. " for " .. m.giver .. (m.metBefore and " again" or "")) or m.title)
            end
        end
    end
    table.sort(timeline, function(a, b) return a.seq < b.seq end)

    local told = 0
    for _, item in ipairs(timeline) do
        local e, m = item.journey, item.moment
        if e then
            if e.type == "zone" and e.continentChanged then
                sentence(say(B.voyage, { from = e.fromContinent or e.from or "home", continent = e.continent or "a new land",
                    zone = e.zone or "?", days = tostring(QH.Pipeline.VOYAGE_DAYS) }), item.day, true)
                told = told + 1
            elseif e.type == "zone" and e.firstVisit then
                sentence(say(B.firstVisit, { zone = e.zone or "?" }), item.day)
                told = told + 1
            elseif e.type == "flight_start" and e.destination then
                sentence(say(B.flight, { dest = e.destination }), item.day)
                told = told + 1
            elseif e.type == "hearth" then
                sentence(say(B.hearth, { home = e.home or "the inn" }), item.day)
                told = told + 1
            elseif e.type == "bind" then
                sentence(say(B.bind, { home = e.home or e.zone or "here" }), item.day)
                told = told + 1
            end
        elseif m then
            local vars = { title = m.title or "the task", place = m.place, instance = m.title or "the depths" }
            vars.Instance = Capitalize(vars.instance)
            told = told + 1
            local t = m.type
            if t == "quest_done" then
                sentence(say(B.taskDone, vars), m.day)
                if m.giver then sentence(say(m.metBefore and B.giverAgain or B.giver, { giver = m.giver })) end
                if m.story then
                    local first = m.story:match("^(.-[%.!?])%s") or m.story
                    if #first < 220 then sentence(say(B.taskStory, { story = first })) end
                end
                titleKind, titleVars = titleKind or "task", titleVars or vars
            elseif t == "quest_accept" then
                sentence(say(B.taskAccepted, vars), m.day)
                if m.giver then sentence(say(m.metBefore and B.giverAgain or B.giver, { giver = m.giver })) end
            elseif t == "death" then
                if m.killer then
                    vars.killer = m.killer
                    sentence(say(B.deathBy, vars), m.day)
                else
                    sentence(say(B.death, vars), m.day)
                end
                titleKind, titleVars = "death", vars
            elseif t == "foe" then
                sentence(say(B.foe, { foe = m.title or "a fierce foe", place = m.place }), m.day)
            elseif t == "spell_learned" then
                sentence(say(B.spellLearned, { spell = m.title or "a new skill" }), m.day)
            elseif t == "money" then
                if m.moneyKind == "milestone" then
                    sentence(say(B.moneyMilestone, { milestone = m.title or "some coin" }), m.day)
                else
                    sentence(say(B.moneySpent, { spent = m.spent or "much of my coin", left = m.left or "little" }), m.day)
                end
            elseif t == "level" then
                sentence(say(B.level, vars), m.day)
            elseif t == "instance_enter" then
                vars.with = m.companions and (" with " .. Join(m.companions)) or ""
                sentence(say(B.dungeon, vars), m.day)
                titleKind, titleVars = titleKind or "dungeon", titleVars or vars
            elseif t == "loot" then
                sentence(say(B.loot, { item = m.title or "something fine" }), m.day)
            elseif t == "reputation" then
                local standing = (m.kind:match("^became (%S+) with") or "friendly")
                sentence(say(B.reputation, { faction = m.title or "the locals", standing = standing, Standing = Capitalize(standing) }), m.day)
            elseif t == "skill" then
                local skill, rank = m.kind:match("^improved their (.+) to (%d+)$")
                skill = skill or "craft"
                sentence(say(B.skill, { skill = skill, Skill = Capitalize(skill), rank = rank or "?" }), m.day)
            elseif t == "achievement" then
                sentence(say(B.achievement, { achievement = m.title or "something" }), m.day)
            elseif t == "camp" then
                sentence(say(B.camp), m.day)
            else
                told = told - 1 -- arrivals are already told by the journey
            end
            if m.touched and #m.touched > 0 then
                local hook = plural(m.touched[1])
                sentence(say(B.fear, { hook = hook, Hook = Capitalize(hook) }))
            end
        end
    end

    if #minors > 0 then
        local list = {}
        for i = 1, math.min(3, #minors) do list[i] = minors[i] end
        sentence(say(B.minor, { list = Join(list) }))
        told = told + 1
    end
    flush()

    if #digest.collapsed > 0 then
        local zones = {}
        for _, c in ipairs(digest.collapsed) do
            local zone = c:match("around (.+)$")
            if zone then table.insert(zones, zone) end
        end
        if #zones > 0 then
            table.insert(paragraphs, say(B.errands, { zones = Join(zones) }))
            told = told + 1
        end
    end

    if told == 0 and #notes == 0 then
        table.insert(paragraphs, say(B.quiet))
    end

    -- Randomized slice-of-life moments (road / combat / town in the body; hearthside at the end).
    local roadFlavors, hearthFlavors = {}, {}
    for _, f in ipairs(digest.flavors or {}) do
        local bank = B.flavor[f.id]
        if bank then
            local variants = bank[voice] or bank.Plain
            local line = Fill(variants[1], f.vars or {})
            if f.slot == "hearth" then
                table.insert(hearthFlavors, line)
            else
                table.insert(roadFlavors, line)
            end
        end
    end
    if #roadFlavors > 0 then
        table.insert(paragraphs, table.concat(roadFlavors, " "))
    end

    -- The player's own notes, in their words.
    for _, m in ipairs(notes) do
        table.insert(paragraphs, say(B.noteIntro) .. (m.note or ""))
        titleKind = titleKind or "note"
    end

    -- Milestones: a short look back.
    if digest.reflections and #digest.reflections > 0 then
        table.insert(paragraphs, say(B.reflection))
    end

    -- Closing: hearthside moment (if any) + the chosen mood or temperament closing.
    local closings = (opts.mood and B.moodClose[opts.mood]) or B.close[temperament] or B.close.default
    local closeLine = closings[pick(#closings)]
    if #hearthFlavors > 0 then
        closeLine = table.concat(hearthFlavors, " ") .. " " .. closeLine
    end
    table.insert(paragraphs, closeLine)

    -- Title
    local voyage
    for _, j in ipairs(digest.journey) do
        if j.event and j.event.type == "zone" and j.event.continentChanged then voyage = j.event end
    end
    local titleBank, vars
    if titleKind == "death" then
        titleBank, vars = B.title.death, titleVars
    elseif voyage then
        titleBank, vars = B.title.voyage, { continent = voyage.continent or "a New Land" }
    elseif titleKind == "task" or titleKind == "dungeon" then
        titleBank, vars = B.title[titleKind], titleVars
    elseif titleKind == "note" then
        titleBank, vars = B.title.note, {}
    else
        titleBank, vars = B.title.quiet, { zone = digest.lastRest.zone or "the Wilds", day = tostring(digest.startDay) }
    end
    local title = Fill(titleBank[pick(#titleBank)], vars or {})

    return { title = title, body = table.concat(paragraphs, "\n\n") }
end

---------------------------------------------------------------------------
-- Chapter summary (no AI)
---------------------------------------------------------------------------
B.chapterOpen = {
    Plain = { "Looking back over these days, from {from} to {to}:", "A few words to remember these days by, from {from} to {to}:" },
    Formal = { "A summary of the days spent between {from} and {to}:", "In review, the period from {from} to {to}:" },
    Poetic = { "From {from} to {to}, the road unrolled like this:", "These are the days between {from} and {to}, as I remember them:" },
    Terse = { "{from} to {to}. Summary:", "Recap. {from}, then {to}." },
}
B.chapterList = {
    Plain = { "I wrote about {list}.", "There was {list}." },
    Formal = { "I recorded {list}.", "Those pages tell of {list}." },
    Poetic = { "The pages remember {list}.", "There was {list}, each a stone on the path." },
    Terse = { "{list}.", "Covered: {list}." },
}
B.chapterClose = {
    Plain = { "On to whatever comes next.", "It feels like a chapter, now that I look at it." },
    Formal = { "So concludes this chapter of my account.", "Thus ends this part of the record." },
    Poetic = { "One chapter closes; the ink is already wet for the next.", "The page turns." },
    Terse = { "Chapter done.", "Next." },
}

function T.ChapterSummary(chapter, profile)
    local voice = VoiceOf(profile)
    local pick = Rng((chapter.number or 1) * 104729)
    local function say(bank, vars)
        local variants = bank[voice] or bank.Plain
        return Fill(variants[pick(#variants)], vars or {})
    end
    local titles = {}
    for _, e in ipairs(chapter.entries) do
        if e.title then table.insert(titles, '"' .. e.title .. '"') end
    end
    while #titles > 6 do table.remove(titles, 1) end
    local zones = chapter.zoneOrder or {}
    local from = zones[1] or "the road"
    local to = zones[#zones] or from
    local body = table.concat({
        say(B.chapterOpen, { from = from, to = to }),
        say(B.chapterList, { list = Join(titles) }),
        say(B.chapterClose),
    }, "\n\n")
    return { title = chapter.mainZone and ("The Days in " .. chapter.mainZone) or "The Road", body = body }
end
