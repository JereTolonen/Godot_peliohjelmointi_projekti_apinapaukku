extends Node3D
## Tason asetukset. Liitä tämä skripti tason juurisolmuun (esim. Level1).

## Ammusten järjestys: ensimmäinen ammutaan ensin, sitten seuraava jne.
## Kun ammukset loppuvat eikä kaikkia apinoita ole kaadettu, taso on hävitty.
##
## Nimi on hahmo-scenen tiedostonimi ilman .tscn-päätettä (kansio scenes/includes/characters),
## esimerkiksi "normal" tai "exploding". Lisää, poista ja järjestä rivejä Inspectorissa.
@export var ammo: PackedStringArray = PackedStringArray(["normal", "normal", "normal", "exploding"])
