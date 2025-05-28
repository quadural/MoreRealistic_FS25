if you want to test the mod from github, you have to download the lastest zip version of the mod, rename the zip file with "MoreRealistic" only (keeping the zip extension if displayed) and copy-paste it to the mods folder of the game.

---------------------------------------------
What is MoreRealistic Mod ?

A deep modification of the game to make it enjoyable for me (especially the driving experience since I want the game to be a "driving farming simulator") 

---------------------------------------------
MoreRealistic history :

IRL, I drove my first tractor at the age of 7 (only the steering wheel, Ford 7000 and IH745)  
I am also a software engineer (but not only)  
I discovered and played LS2009 just before Farming Simulator 2011 was released  
I started modding with FS2011 -> the game physics was too bad (unrealistic flying tractor. The more weight on the wheels, the more power you get, no rolling resistance, etc etc)  
So, I created MR11 to get the best driving experience from the vanilla game (and fix many bugs like the farm bales elevator). Once FS2011 with MR was feeling great to me, I released MR11.  
But it was a bit late : Farming Simulator 2013 was released too, it took me "ages" to make MR11 (thousands hours).  
Then, I worked on MR13 because vanilla FS2013 was feeling so bad compared to MR11. Another time, it took me a bunch of time to get the "MR engine" ready, and then, I had to convert every piece of equipment to be "MR"... And then expansion vehicles...  
And so, I spent another couple of thousand hours on this one.  
When FS15 was released, I gave it a try : still not good, I could not feel I was driving a tractor. I check what could be done with modding, but didn't achieve to do anything good (didn't even achieve to apply proper gravity) => so no MR15  
When FS17 was released, it feeled the same. As usual, it was like playing with "playmobil" tractors. I achieve to make MR17 and spent a lot of time to convert vehicles. Of course, there were even more vehicles than before = I guess I spent the most time on this one (more than 3000 hours ?)  
At the end = I spent all my free time to this mod, but did not have time to enjoy the game with it...  
Then, FS19 was released => I had a new job, and no time for playing (more than full-time job = 3000 hours per year). So, no MR  
The same for FS22 => same job and still no time for FS or MR.  

---------------------------------------------
Why MR25 ?

I bought the game just before release, I achieved to play almost one hour before trying to mod the game.
The driving experience was too bad :
* Just set manual direction change to "ON", and try to cultivate a field with base MT635 = unplayable. Each time you shift in reverse, the R1 speed is selected (crawling) and you have to shift all the gears up to get a decent reverse speed. It quickly become unbearable.
* IRL, John Deere 3650 is one of "my" tractor (spent a couple hundred hours driving it) => gearbox is "badly" set in game. (hi-lo lever is not in the right direction, and it feels like driving a powershift tractor). Gears ratio differences have also nothing to do with IRL, I couldn't feel driving a 3650
* MF 8570 harvesting at 10kph whatever the yield, the crop, the incline...
* I bought a Fendt (vario transmission) : driving experience was "disgusting" (in 2 words : flat and dull)
* This was already more than I could handle : the "simulator" word was lost

---------------------------------------------
What can you expect from MoreRealistic ?

* rolling resistance (something not present in base game engine, but really, really, really important IRL for farming vehicles) // air resistance too, but not so important
* better tire forces (example : no more possible to pull more than your weight)
* earth gravity (this was not the case in base game FS2011 and 2013)
* IRL mass (realistic fillType density, no mass limit, better center of mass)
* More realistic harvest and working speed (still a bit "easy" compared to IRL, but you will want that high horse power shinny tractor or bigger combine now.)
* Engine with proper torque curve (try to compare John Deere 3650 and Landini REX4 120 with or without MR, at work in a hilly field)
* new transmission management (MR game engine make use of its own function, for automatic shifting too = far more realistic - try making 0-40kph with the MT635 with or without MR, automatic shifting ON) => it can handle hydrostatic transmission (drive 30 seconds the Massey Ferguson 8570 on road without MR and with MR => if you love driving by yourself : difficult to get back to base game feeling)
* no automatic brake when going downhill and going faster than max vehicle speed - let's hope AI is able to brake now
* MR Combines take into account "liters per second" and crops (less yield = faster combine speed. Harvesting less than 100% of the header width = more speed).
* MR Combines are limited by : header max cut speed, combine threshing capacity, engine power (chopping straw = consume more power = maybe less speed if the combine is underpowered in the current crop)
* variable center of mass depending on the fill level
* tires do have a great impact in game now (Example : just try to cross a wet field with a full trailer fitted with narrow road tires)

---------------------------------------------
What should you not expect from MoreRealistic ?

* overriding every piece of equipment in the game, the expansion, the official mods... (It would require me more than 24 hours a day to achieve that in an acceptable time)


---------------------------------------------
Fun facts
* I bought the game on Steam first. And then, I had to buy it directly from Giants because modding is not welcome on the steam version of the game... (no lua game source)
* Each MoreRealistic project is started from scratch. I do not copy code from previous game.
* It can take me dozens of hours (hundred ?) to remove some unwanted vanilla features that would take Giants minutes to remove (say hello FS2011 "damping" value)
* It seems every piece of equipment I look at is "wrong" (maybe I look too much ?) :
  * APE50 is not CVT driven IRL (manual gearbox like a motorbike, but shifting lever = rotating the whole left handle. And then, you have a reverser lever.)
  * Aprilia 125 is not 100Hp at all IRL (especially the current 4 strokes engine)
  * Landini REX4 is not a GT version (this is a F version in game)
  * Amazone Spreader is not a 3200 model (this is the 2600 version : not the same width at all)
  * GreatPlains 1500 has the wrong optionnal attachment : this is not a fertilizer unit ! this is the small seeds attachement unit
  * Challenger MT635/645 and MT655/665 = not the same engine ! sisu 7.4L and 8.4L / not the same transmission : funk 18/6 and 18/9 (and so, not the same weight either)
* In base game, more than 90% of vehicles share the same engine (same torque curve, just a factor applied to derate the power). You can't feel the difference between a 8.4L valmet engine and a 3.6L deutz engine => this is not a wanted experience for a driving simulator, especially with manual gears
* A few times, MR25 has been stopped (nearly aborted) because I didn't achieve to "bend" the base game engine like I wanted
* With base game engine, when playing with Giants studio attached to debug and "vehicleDebug" active, the game engine is eating your memory (RAM) => this is fixed with MR engine
* MR is best suited for "hardcore" players who play vanilla game and don't spend time searching for mods => the ones that would never know MR exists
