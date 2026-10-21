// Data shapes shared between the addon (SavedVariables) and the companion.

export type EventType =
  | "quest_accept"
  | "quest_done"
  | "zone"
  | "instance_enter"
  | "instance_leave"
  | "flight_start"
  | "flight_end"
  | "hearth"
  | "bind"
  | "level"
  | "death"
  | "rest";

export interface PartyMember {
  name: string;
  class?: string;
}

/** One recorded story event, as written by the addon (Data.lua / Capture.lua / Rest.lua). */
export interface QHEvent {
  seq: number;
  t: number; // server time (epoch seconds)
  type: EventType | string;
  level?: number;
  zone?: string;
  subzone?: string;
  mapID?: number;
  continent?: string;
  // quests
  questID?: number;
  title?: string;
  text?: string;
  objectives?: string;
  rewardText?: string;
  questLine?: string;
  questLineID?: number;
  questLevel?: number;
  suggestedGroup?: number;
  frequency?: number;
  tag?: string;
  elite?: boolean;
  party?: PartyMember[];
  // travel
  from?: string;
  fromContinent?: string;
  firstVisit?: boolean;
  continentChanged?: boolean;
  destination?: string;
  home?: string;
  instance?: string;
  instanceType?: string;
  // rest
  kind?: "rested" | "campfire" | string;
  how?: "logout" | "manual" | string;
}

export interface TRP3Snapshot {
  profileName?: string;
  firstName?: string;
  lastName?: string;
  title?: string;
  fullTitle?: string;
  race?: string;
  class?: string;
  age?: string;
  eyes?: string;
  height?: string;
  weight?: string;
  birthplace?: string;
  residence?: string;
  misc?: { name: string; value: string }[];
  personality?: { left: string; right: string; leftStrength: number; max: number }[];
  about?: {
    template?: number;
    text?: string;
    sections?: string[];
    physical?: string;
    personality?: string;
    history?: string;
  };
  currently?: string;
  version?: string;
}

export interface QHProfile {
  source: "trp3" | "manual";
  name: string;
  useGameName?: boolean;
  class: string;
  useGameClass?: boolean;
  traits?: Partial<Record<"temperament" | "outlook" | "upbringing" | "drive" | "voice", string>>;
  fear?: string;
  past?: string;
  trp3?: TRP3Snapshot;
  createdAt?: number;
  updatedAt?: number;
}

export interface QHMeta {
  name: string;
  realm?: string;
  class?: string;
  classFile?: string;
  race?: string;
  raceFile?: string;
  sex?: number; // 2 male, 3 female
  faction?: string;
  level?: number;
}

export interface QHCharacter {
  events: QHEvent[];
  nextSeq: number;
  meta?: QHMeta;
  profile?: QHProfile;
  state?: Record<string, unknown>;
}

export interface QHSavedVariables {
  version?: number;
  characters: Record<string, QHCharacter>;
}

/** A finished journal entry (stored by the companion, mirrored into Entries.lua). */
export interface JournalEntry {
  id: string;
  restSeq: number;
  day: number;
  dayEnd: number;
  title: string;
  body: string;
  zone?: string;
  subzone?: string;
  restKind?: string;
  level?: number;
  t: number; // real time of the rest (epoch seconds)
}
