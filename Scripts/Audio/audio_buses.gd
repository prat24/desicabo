## AudioBuses — names of the mixer buses the game routes sound through.
## AudioSettings creates them at startup and drives their volume.
class_name AudioBuses
extends RefCounted

const MASTER := "Master"
const MUSIC := "Music"
const SFX := "SFX"
