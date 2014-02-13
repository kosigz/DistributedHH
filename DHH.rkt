;; The first three lines of this file were inserted by DrRacket. They record metadata
;; about the language level of this file in a form that our tools can easily process.
#reader(lib "htdp-advanced-reader.ss" "lang")((modname |FINAL HH|) (read-case-sensitive #t) (teachpacks ()) (htdp-settings #(#t constructor repeating-decimal #t #t none #f ())))

; @author: Konstantin Gizdarski
; @date: 06 December 2013
; @org: Northeastern University CS 2500 F'2013
; ------------------------------------------------------------------------------
(require 2htdp/image)
(require 2htdp/universe)
; ------------------------------------------------------------------------------
;         _______ _       _______         
; |\     /(  ____ ( (    /(  ____ )\     /|
; | )   ( | (    \/  \  ( | (    )( \   / )
; | (___) | (__   |   \ | | (____)|\ (_) / 
; |  ___  |  __)  | (\ \) |     __) \   /  
; | (   ) | (     | | \   | (\ (     ) (   
; | )   ( | (____/\ )  \  | ) \ \__  | |   
; |/     \(_______//    )_)/   \__/  \_/
; ------------------------------------------------------------------------------
; Hungry Henry is a multi-player distributed game programmed in Advanced Student
; Language, a variation of Racket created for educational purposes. Players race
; around a map collecting cupcakes. When all the cupcakes have been eaten, the
; game is over. The player who has eaten the most cupcakes wins.

; ------------------------------------------------------------------------------
; TABLE OF CONTENTS
; ------------------------------------------------------------------------------
; 0. NOTES ON STYLE
; 1. SAMPLING THE GAME
; 2. CONSTANTS
; 3. DATA DEFINITIONS
; -- A. GLOBAL DATA DEFINITIONS
; -- B. CLIENT DATA DEFINITIONS
; -- C. SERVER DATA DEFINITIONS
; 4. CLIENT - MAIN FUNCTION
; 5. CLIENT - HANDLER FUNCTIONS
; 6. CLIENT - UTILITIES
; -- A. RENDERING THE WORLD
; -- B. INTERPRETING SERVER MESSAGES
; 7. SERVER - MAIN FUNCTION
; 8. SERVER - HANDLER FUNCTIONS
; 9. SERVER - UTILITIES
; -- A. INITIALIZING THE UNIVERSE
; -- B. MOVING THE PLAYERS
; -- C. INCREMENTING SCORES
; -- D. EATING CUPCAKES
; -- E. TELLING THE CLIENTS TO WAIT
; -- F. COMBINING ALL THE ACTION AND SENDING IT OFF
; -- G. ENDING THE GAME
; -- H. ADDING WAYPOINTS
; 10. DATA FOR TESTING ; NOTE: put data defined specifically for tests at the
; -- A. CLIENT DATA    ; end to improve readability and bc its ugly.
; -- B. SERVER DATA 

; ------------------------------------------------------------------------------
; SECTION 0. NOTES ON STYLE
; ------------------------------------------------------------------------------
; (1) The program is implemented top-down. Utilties are grouped by purpose and
; developed top-down. Helpers to the utility functions are ordered in the same
; way the problem is naturally reduced.

; (2) Should any of a function's check expects be longer than one line, all 
; check expects are placed after the function definition.

; (3) Most functions have three check-expects. Some with especially tedious but 
; not so informative ones have only one. Several other functions have six. There
; is no black code when the program is run.

; ------------------------------------------------------------------------------
; SECTION 1. SAMPLING THE GAME
; ------------------------------------------------------------------------------
; A server is run on one computer using the (make-game Number Number) function. 
; Players can then join the game by running the (join-game String String) 
; function with a desired username and the IP address of the machine on which
; the server is running.
#;(launch-many-worlds (make-game 3 20)
                      (join-game "A" LOCALHOST)
                      (join-game "B" LOCALHOST)
                      (join-game "C" LOCALHOST))
; You can try the game by copying the above code into the console. This will
; run the game with three players and twenty cupcakes on a single machine.

; ------------------------------------------------------------------------------
; SECTION 2. CONSTANTS
; ------------------------------------------------------------------------------
; Scaling Constants
(define WIDTH 600) ; interp. specifies width of game-space
(define HEIGHT 600) ; interp. specifies height of game-space
(define WAYPOINTR 6) ; interp. specifies radius of each waypoint

; Image Constants
(define BACKGROUND (empty-scene WIDTH HEIGHT)) 
; interp. the background image upon which the client's state is drawn.
(define PLAYER (square 20 'solid 'red)) 
; interp. the visual representation of the player corresponding to the client
(define OTHER-PLAYERS (square 20 'solid 'blue))
; interp. the visual representation of all other players.
(define WAYPOINT (overlay 
                  (circle (/ WAYPOINTR 1.5) 'solid 'white) 
                  (circle WAYPOINTR 'solid 'red)))
; interp. the visual representation of a waypoint.
(define CUPCAKE (circle 8 'solid 'green))
; interp. the visual representation of a cupcake.

; Movement Contants
(define SPEED 5) ; interp. the max distance which a player moves per tick.

; ------------------------------------------------------------------------------
; SECTION 3. DATA DEFINITIONS
; ------------------------------------------------------------------------------
; A. GLOBAL DATA DEFINITIONS
; ------------------------------------------------------------------------------
; A Cupcake, a Waypoint, and a Posn are (make-posn Number Number)
; A Score is a Natural

; A Client2Server is
; -- (list 'waypoint (list Number Number))
; interp. indicates to the universe that the client has clicked at a location,
; where the location is represented as a list of two numbers

; A Server2Client is one of
; -- (list 'wait Natural)
; interp. indicates to the world that the server is currently waiting for the 
; given number of players to join the game.
; -- (list 'world (list Number Number) [List-of [List-of Number]] 
;    [List-of [List-of Number]] [List-of [List-of Number]])
; interp. sends the world all the information it needs to render the world for
; the player in the form of an S-expression. 
; The first list of numbers is the location of the particular player. 
; The second list of lists of numbers is that player's waypoints. 
; The third list of lists is the locations of all other players. 
; The final list is the location of the cupcakes.
; -- (list 'end Boolean)
; interp. indicates that all cupcakes have been eaten. Tells the player whether
; they win or lose. True for win, false for lose.

; B. CLIENT DATA DEFINITIONS
; ------------------------------------------------------------------------------
(define-struct hhclient (location waypoints others cupcakes))
; An HHClient is one of:
; -- 'none
; interp. indicates the client has been initialized but the server has not
; responded by giving it a state.
; -- Number
; interp. the world's representation before the game has started is the number
; of players the world is still waiting for.
; -- (make-hhclient Posn [List-of Posn] [List-of Posn] [List-of Posn])
; interp. the way the world is represented during the game.
; The given posn is the location of the particular player.
; The first list of posns is the locations of all that player's waypoints.
; The second list of posns is the locations of all other players.
; The third list of posns is the locations of all the cupcakes.
; -- Boolean
; inetrp. whether this player has successfully eaten the most cupcakes. If the
; given player wins, it will be true, else false.

; A HandlerResult is one of:
; -- HHState
; -- (make-pacakge HHState S-expression)
; interp. either our defined world state or our defined world state wrapped 
; with some information we want the server to get contained in a package

; C. SERVER DATA DEFINITIONS
; ------------------------------------------------------------------------------
(define-struct hhserver (players cupcakes num started?))
; An HHServer is
; -- (make-hhserver [List-of Player] [List-of Cupcake] Number Boolean)
; interp. a structure that wraps the state of the server. It contains a list of
; players, as defined below, and a list of cupcakes, which are just locations.
; It also contains a number, which is how many players the game is intended for,
; and a boolean, indicatng whether the game has been started.
; NOTE: once the game has been started, d/c-ing players will not cause the world
; to wait for new players to join

(define-struct pl (world location waypoints score))
; A Player is 
; -- (make-pl IWorld Posn [List-of Waypoint] Score)
; interp. a structure that contains all the information about a given player.
; Includes the player's IWorld
; A Posn representing his or her location
; A List-of Waypoints in the order that the player will visit them
; A Score which is the number of cupcakes that player has eaten

; A UniverseBundle is
; -- (make-bundle HHServer [List-of Mail] [List-of IWorld])
; interp. the first element is the server state, the next is a list of mail, and
; the last is a list of IWorld to be dropped or "killed"

; A [Maybe X] is one of:
; -- false
; -- X
; interp. a generic data definition for any type of data or false.

; ------------------------------------------------------------------------------
;  _______  _       _________ _______  _       _________
; (  ____ \( \      \__   __/(  ____ \( (    /|\__   __/
; | (    \/| (         ) (   | (    \/|  \  ( |   ) (   
; | |      | |         | |   | (__    |   \ | |   | |   
; | |      | |         | |   |  __)   | (\ \) |   | |   
; | |      | |         | |   | (      | | \   |   | |   
; | (____/\| (____/\___) (___| (____/\| )  \  |   | |   
; (_______/(_______/\_______/(_______/|/    )_)   )_( 
; ------------------------------------------------------------------------------
; The client has two functions in Distributed Hungry Henry:
; (1) To serve as an interface for the player's clicks, sending them off to the
; server to add to that player's representation.
; (2) To render the current world state as conveyed by the server. Notably, it 
; cannot move anything without authentication from the server.

; ------------------------------------------------------------------------------
; SECTION 4. CLIENT - MAIN FUNCTION
; ------------------------------------------------------------------------------
; join-game: String -> Boolean
; interp. accepts a username and the server's IP address. Runs big-bang world.
; Ultimately returns whether the player has won or not, its final world state.
; NOTE: the client will only return a boolean if the game is played to
; completion. Otherwise, it will return an HHClient.
(define (join-game username ip-address)
  (big-bang 'none
            (to-draw render)
            (on-tick tock)
            (on-receive process-pkg)
            (on-mouse add-waypoint)
            (name username)
            (register ip-address)))

; ------------------------------------------------------------------------------
; SECTION 5. CLIENT - HANDLER FUNCTIONS
; ------------------------------------------------------------------------------
; render: HHState -> Image
; interp. a to-draw handler function which renders the current world state based
; on its type
(define (render client)
  (cond
    [(and (symbol? client) (symbol=? client 'none)) 
     (render-none client)]
    [(number? client)
     (render-waiting client)]
    [(boolean? client)
     (render-boolean client)]
    [(hhclient? client)
     (render-client client)]))
(check-expect (render BLANK-CLIENT)
              (overlay (text/font "Waiting for server..." 25 'black "Sans Serif"
                                  'swiss 'normal 'bold #f) BACKGROUND))
(check-expect (render NUMERICAL-CLIENT) 
              (overlay (text/font "Waiting for 2 more clients to join." 25 
                                  'black "Sans Serif" 'swiss 'normal 'bold #f) 
                       BACKGROUND))
(check-expect (render STRUCTURE-CLIENT)
              (place-image PLAYER 300 300
                           (place-lop 
                            (list (make-posn 150 150) (make-posn 450 150))
                            WAYPOINT
                            (place-lop 
                             (list (make-posn 150 450) (make-posn 450 450))
                             OTHER-PLAYERS
                             (place-lop 
                              (list (make-posn 550 450) (make-posn 450 550))
                              CUPCAKE
                              BACKGROUND)))))
(check-expect (render true)
              (overlay 
               (text/font "You win!" 25 'black
                          "Sans Serif" 'swiss 'normal 'bold #f) BACKGROUND))

; tock: HHState -> HandlerResult
; interp. an on-tick handler is required by Big Bang. However, we do not
; need it to do anything. Thus, this function was born.
(check-expect (tock BLANK-CLIENT) BLANK-CLIENT)
(check-expect (tock NUMERICAL-CLIENT) NUMERICAL-CLIENT)
(check-expect (tock STRUCTURE-CLIENT) STRUCTURE-CLIENT)
(define (tock game)
  game)

; process-pkg: HHState Server2Client -> HandlerResult
; interp. changes the world state based on the given message
(define (process-pkg client server2client)
  (cond
    [(symbol=? (first server2client) 'wait) 
     (second server2client)]
    [(symbol=? (first server2client) 'world)
     (mail->client server2client)]
    [(symbol=? (first server2client) 'end)
     (second server2client)]))
(check-expect (process-pkg BLANK-CLIENT BASIC-S2C) 5)
(check-expect (process-pkg NUMERICAL-CLIENT AN-S2C) 
              (make-hhclient (make-posn 100 100) empty empty empty))
(check-expect (process-pkg STRUCTURE-CLIENT ANOTHER-S2C)
              (make-hhclient (make-posn 1 2) 
                             (list (make-posn 3 4) 
                                   (make-posn 5 6)) 
                             (list (make-posn 7 8) 
                                   (make-posn 9 10)) 
                             (list (make-posn 11 12) 
                                   (make-posn 13 14))))
(check-expect (process-pkg STRUCTURE-CLIENT (list 'end true)) true)

; add-waypoint: HHState Number Number MouseEvent -> HandlerResult
; interp. processes an added waypoint and sends it to the server, if the
; game is running.
(define (add-waypoint client x y event)
  (cond 
    [(and (hhclient? client) (string=? event "button-down"))
     (make-package client (list 'wp (list x y)))]
    [else client]))
(check-expect (add-waypoint BLANK-CLIENT 7 7 "button-down") BLANK-CLIENT)
(check-expect (add-waypoint STRUCTURE-CLIENT 7 7 "bogus") STRUCTURE-CLIENT)
(check-expect (add-waypoint STRUCTURE-CLIENT 7 7 "button-down")
              (make-package STRUCTURE-CLIENT (list 'wp (list 7 7))))

; ------------------------------------------------------------------------------
; SECTION 6. CLIENT - UTILITIES
; ------------------------------------------------------------------------------
; A. RENDERING THE WORLD
; ------------------------------------------------------------------------------
; render-none: HHClient -> Image
; interp. draws the world before it has been initialized.
(define (render-none client)
  (overlay (text/font "Waiting for server..." 25 'black
                      "Sans Serif" 'swiss 'normal 'bold #f) BACKGROUND))
(check-expect (render-none BLANK-CLIENT)
              (overlay (text/font "Waiting for server..." 25 'black
                                  "Sans Serif" 'swiss 'normal 'bold #f) 
                       BACKGROUND))

; render-waiting: HHClient -> Image
; interp. draws the world if it is waiting for more clients to join. Shows the
; user how many clients are required before the game can begin.
(define (render-waiting client)
  (cond
    [(> client 0) (overlay 
                   (text/font 
                    (string-append "Waiting for "
                                   (number->string client)
                                   " more clients to join.") 
                    25 'black
                    "Sans Serif" 'swiss 'normal 'bold #f) BACKGROUND)]
    [else (overlay (text/font "The game is starting..." 25 'black
                              "Sans Serif" 'swiss 'normal 'bold #f) 
                   BACKGROUND)]))
(check-expect (render-waiting NUMERICAL-CLIENT) 
              (overlay (text/font "Waiting for 2 more clients to join." 25 
                                  'black "Sans Serif" 'swiss 'normal 'bold #f) 
                       BACKGROUND))
(check-expect (render-waiting 0) 
              (overlay (text/font "The game is starting..." 25 'black
                                  "Sans Serif" 'swiss 'normal 'bold #f) 
                       BACKGROUND))

; render-boolean: HHClient -> Image
; interp. draws the world if the game is over and the player has won or lost.
(define (render-boolean client)
  (cond
    [(equal? true client)
     (overlay (text/font "You win!" 25 'black
                         "Sans Serif" 'swiss 'normal 'bold #f) BACKGROUND)]
    [else
     (overlay (text/font "You lose!" 25 'black
                         "Sans Serif" 'swiss 'normal 'bold #f) BACKGROUND)]))
(check-expect (render-boolean true)
              (overlay (text/font "You win!" 25 'black
                                  "Sans Serif" 'swiss 'normal 'bold #f) 
                       BACKGROUND))
(check-expect (render-boolean false)
              (overlay (text/font "You lose!" 25 'black
                                  "Sans Serif" 'swiss 'normal 'bold #f) 
                       BACKGROUND))

; render-client: HHClient -> Image
; interp. a to-draw helper which is used to render the client's state if it
; is an HHClient structure
(define (render-client game)
  (local [(define loc (hhclient-location game))]
    (place-image PLAYER (posn-x loc) (posn-y loc)
                 (place-lop (hhclient-waypoints game) WAYPOINT
                            (place-lop (hhclient-others game) OTHER-PLAYERS
                                       (place-lop (hhclient-cupcakes game)
                                                  CUPCAKE
                                                  BACKGROUND))))))
(check-expect (render-client STRUCTURE-CLIENT)
              (place-image PLAYER 300 300
                           (place-lop 
                            (list (make-posn 150 150) (make-posn 450 150))
                            WAYPOINT
                            (place-lop 
                             (list (make-posn 150 450) (make-posn 450 450))
                             OTHER-PLAYERS
                             (place-lop 
                              (list (make-posn 550 450) (make-posn 450 550))
                              CUPCAKE
                              BACKGROUND)))))

; place-lop: [List-of Posn] Image Image -> Image
; interp. places the first image at every posn in the list of posns on top of
; the background.
(define (place-lop posns image bckgrnd)
  (foldl (λ (p b) (place-image image (posn-x p) (posn-y p) b)) bckgrnd posns))
(check-expect (place-lop '() WAYPOINT (empty-scene 30 30))
              (empty-scene 30 30))
(check-expect (place-lop `(,(make-posn 15 15)) WAYPOINT (empty-scene 30 30))
              (place-image WAYPOINT 15 15 (empty-scene 30 30)))
(check-expect (place-lop `(,(make-posn 10 10) 
                           ,(make-posn 20 20)) WAYPOINT (empty-scene 30 30))
              (place-image WAYPOINT 10 10 
                           (place-image WAYPOINT 20 20 (empty-scene 30 30))))

; B. INTERPRETING SERVER MESSAGES
; ------------------------------------------------------------------------------
; mail->client: Sever2Client -> HHClient
; interp. a function that converts mail received from the server into a client
; structure, representing the world's current state
(define (mail->client server2client)
  (make-hhclient (list->posn (second server2client))
                 (to-posn-list (third server2client))
                 (to-posn-list (fourth server2client))
                 (to-posn-list (fifth server2client))))
(check-expect (mail->client AN-S2C)
              (make-hhclient (make-posn 100 100) empty empty empty))
(check-expect (mail->client ANOTHER-S2C)
              (make-hhclient (make-posn 1 2) 
                             (list (make-posn 3 4) 
                                   (make-posn 5 6)) 
                             (list (make-posn 7 8) 
                                   (make-posn 9 10)) 
                             (list (make-posn 11 12) 
                                   (make-posn 13 14))))

; to-posn-list: [List-of [List-of Number]] -> [List-of Posn]
; interp. takes a list of lists of numbers  
; ASSUME each list of numbers has exactly two numbers
(define (to-posn-list a-list-of-lists)
  (map list->posn a-list-of-lists))
(check-expect (to-posn-list '((0 0))) (list (make-posn 0 0)))
(check-expect (to-posn-list '((1 2) (3 4))) 
              (list (make-posn 1 2) (make-posn 3 4)))
(check-expect (to-posn-list '((0 0) (1 1) (2 2)))
              (list (make-posn 0 0) (make-posn 1 1) (make-posn 2 2)))

; list->posn: [List-of Number] -> Posn
; interp. takes a list that wraps two numbers and converts into a posn
; ASSUME the given list of numbers has exactly two numbers
(check-expect (list->posn '(1 1)) (make-posn 1 1))
(check-expect (list->posn '(50 50)) (make-posn 50 50))
(check-expect (list->posn '(100 100)) (make-posn 100 100))
(define (list->posn num-list)
  (make-posn (first num-list) (second num-list)))

; ------------------------------------------------------------------------------
;  _______  _______  _______           _______  _______ 
; (  ____ \(  ____ \(  ____ )|\     /|(  ____ \(  ____ )
; | (    \/| (    \/| (    )|| )   ( || (    \/| (    )|
; | (_____ | (__    | (____)|| |   | || (__    | (____)|
; (_____  )|  __)   |     __)( (   ) )|  __)   |     __)
;       ) || (      | (\ (    \ \_/ / | (      | (\ (   
; /\____) || (____/\| ) \ \__  \   /  | (____/\| ) \ \__
; \_______)(_______/|/   \__/   \_/   (_______/|/   \__/
; ------------------------------------------------------------------------------
; The server manages the entirety of the game. It processes new players joining,
; and launches the game when there are enough. While the game is running, it 
; moves each player, increments his or her score, and eats all surrounding
; cupcakes every clock tick. It also sends all the information about locations
; back to the clients, which can update what they are displaying. As soon as all
; cupcakes are eaten, the server sends the player with the highest score a msg
; indicating he or she has won. All others are notified that they have lost.

; ------------------------------------------------------------------------------
; PART 7. SERVER - MAIN FUNCTION
; ------------------------------------------------------------------------------
; make-game: Natural -> HHServer
; interp. runs a universe for the given number of players. Waits for the given
; number of players to join before running the game. Returns the HHServer's
; state when the universe is closed.
(define (make-game num-players num-cupcakes)
  (universe (make-hhserver empty 
                           (make-randoms num-cupcakes) num-players false)
            (on-tick tick-handler)
            (on-msg process-msg)
            (on-new add-world)))

; ------------------------------------------------------------------------------
; PART 8. SERVER - HANDLER FUNCTIONS
; ------------------------------------------------------------------------------
; tick-handler: HHServer -> UniverseBundle
; interp. advances the universe by a single state.
; In order: moves all avatars, updates all the scores, removes all overlapped
; cupcakes, and finally sends the updates world states to all of the worlds.
(define (tick-handler server)
  (cond
    [(hhserver-started? server)
     (cond
       [(empty? (hhserver-cupcakes server))
        (end-universe server)]
       [else 
        (advance-universe server)])]
    [else (wait-universe server)]))
(check-within (tick-handler SAMPLE-SERVER)
              (make-bundle
               NEXT-TICK
               NEXT-MAIL
               empty) 1)
(check-expect (tick-handler UNFILLED-SERVER)
              (make-bundle
               UNFILLED-SERVER
               WAIT-MAIL
               empty))
(check-expect (tick-handler NO-CUPCAKE-SERVER)
              (make-bundle NO-CUPCAKE-SERVER
                           END-MAIL
                           empty))

; process-msg: HHServer IWorld Client2Server -> UniverseBundle
; interp. processes a recieved message from a client. This will always be
; a new waypoint, which we hand off to the add-wp-to-player function.
(define (process-msg server iworld message)
  (local [(define new-waypoint (list->posn (second message)))]
    (make-bundle
     (make-hhserver
      (add-wp-to-player (hhserver-players server) iworld new-waypoint)
      (hhserver-cupcakes server)
      (hhserver-num server)
      (hhserver-started? server))
     empty
     empty)))
(check-expect (process-msg SAMPLE-SERVER iworld3 CLIENT2SERVER)
              (make-bundle
               (make-hhserver
                (list
                 (make-pl iworld1 (make-posn 50 50) 
                          (list (make-posn 50 53)) 10)
                 (make-pl iworld2 (make-posn 250 250) 
                          (list (make-posn 55 50)) 0)
                 (make-pl iworld3 (make-posn 150 150) 
                          (list (make-posn 10 10)) 0))
                (list (make-posn 30 30) (make-posn 40 40) (make-posn 50 50))
                3
                true)
               empty
               empty))

; add-world: HHServer IWorld -> UniverseBundle
; interp. registers a given world with the server, if there are fewer than
; the specified number of players AND if the world is not yet started.
; As stated earlier, it is a stylistic choice to not allow new players to
; join after the world has been started.
(define (add-world server an-iworld) 
  (cond
    [(and (> (hhserver-num server) (length (hhserver-players server)))
          (not (hhserver-started? server)))
     (make-bundle (make-hhserver (cons (make-random-player an-iworld)
                                       (hhserver-players server))
                                 (hhserver-cupcakes server)
                                 (hhserver-num server)
                                 (hhserver-started? server))
                  empty
                  empty)]
    [else (make-bundle server empty empty)]))
(check-expect (add-world SAMPLE-SERVER iworld2) 
              (make-bundle SAMPLE-SERVER empty empty))
(check-within (add-world ANOTHER-UNFILLED-SERVER iworld2)
              (make-bundle
               (make-hhserver (list (make-pl iworld2 (make-posn 0 0) empty 0)
                                    (make-pl iworld1 (make-posn 50 50) 
                                             (list (make-posn 50 53)) 10)) 
                              empty 2 false)
               empty
               empty) 600)

; ------------------------------------------------------------------------------
; PART 9. CLIENT - UTILITIES
; ------------------------------------------------------------------------------
; A. INITIALIZING THE UNIVERSE
; ------------------------------------------------------------------------------
; make-random-player: IWorld -> Player
; interp. creates a new player with an empty list waypoints and a score of zeros
; at a random position within the defined game-space.
(define (make-random-player an-iworld)
  (make-pl an-iworld
           (random-posn WIDTH HEIGHT)
           empty
           0))
(check-expect (pl? (make-random-player iworld1)) true)
(check-within (make-random-player iworld1)
              (make-pl iworld1 (make-posn 300 300) empty 0) 300)

; make-randoms: Natural -> [List-of Posn]
; interp. generates a list of n random posns, where x and y are < W and H resp,
; using random-posn.
(check-expect (posn? (first (make-randoms 2))) true)
(check-expect (cons? (first (make-randoms 2))) false)
(check-expect (length (make-randoms 4)) 4)
(define (make-randoms n)
  (cond
    [(< n 1) empty]
    [else (cons (random-posn WIDTH HEIGHT)
                (make-randoms (sub1 n)))]))

; random-posn: Number Number -> Posn
; interp. creates a random posn within the given (x, y) coordinate pair.
(check-expect (posn? (random-posn 50 50)) true)
(check-expect (>= 50 (posn-x (random-posn 50 50))) true)
(check-expect (<= 0 (posn-x (random-posn 50 50))) true)
(define (random-posn x y)
  (make-posn (random x) (random y)))

; B. MOVING THE PLAYERS
; ------------------------------------------------------------------------------
; move-all-avatars: HHServer -> HHServer
; interp. moves all avatars toward their next waypoint per the move-avatar.
(define (move-all-avatars server)
  (make-hhserver
   (map move-avatar (hhserver-players server))
   (hhserver-cupcakes server)
   (hhserver-num server)
   (hhserver-started? server)))
(check-within (move-all-avatars SAMPLE-SERVER)
              (make-hhserver
               (list
                (make-pl iworld1 (make-posn 50 53) empty 10)
                (make-pl iworld2 
                         (make-posn #i246.5094993193523 #i246.4199993018998) 
                         (list (make-posn 55 50)) 0)
                (make-pl iworld3 (make-posn 150 150) empty 0))
               (list (make-posn 30 30) (make-posn 40 40) (make-posn 50 50))
               3
               true) 
              0.1)

; move-avatar: Player -> Player
; interp. moves a single player toward his or her next waypoint at the defined
; rate. If the distance is smaller than the rate, the waypoint is removed and
; the player is teleported to the location.
(define (move-avatar player)
  (local [(define D-NEXT (distance-to-next player))]
    (cond
      [(boolean? D-NEXT) player]
      [(> (expt SPEED 2) D-NEXT)
       (make-pl (pl-world player)
                (first (pl-waypoints player))
                (rest (pl-waypoints player))
                (pl-score player))]
      [else
       (make-pl (pl-world player)
                (move-toward (pl-location player)
                             (first (pl-waypoints player)))
                (pl-waypoints player)
                (pl-score player))])))
(check-within (move-avatar MATTHIAS)
              (make-pl iworld2 
                       (make-posn #i246.5094993193523 #i246.4199993018998) 
                       (list (make-posn 55 50)) 0) 0.1)
(check-expect (move-avatar AMAL)
              (make-pl iworld3 (make-posn 150 150) empty 0))
(check-within (move-avatar KOSI)
              (make-pl iworld1 (make-posn 50 53) empty 10) 0.1)

; move-posn: Posn Posn -> Posn
; interp. moves the first posn toward the second posn at the prescribed rate.
(check-within (posn-x (move-toward (make-posn 30 30) (make-posn 30 45))) 30 1)
(check-within (posn-y (move-toward (make-posn 30 30) (make-posn 30 45))) 35 1)
(check-within (posn-x (move-toward (make-posn 30 30) (make-posn 45 30))) 35 1)
(check-within (posn-y (move-toward (make-posn 30 30) (make-posn 45 30))) 30 1)
(check-within (posn-x (move-toward (make-posn 30 30) (make-posn 15 30))) 25 1)
(check-within (posn-y (move-toward (make-posn 30 30) (make-posn 30 15))) 25 1)
(define (move-toward location target)
  (local [(define ANGLE (atan (abs (- (posn-y target) (posn-y location)))
                              (abs (- (posn-x target) (posn-x location)))))
          ; (Number -> Number) (Posn -> Number) -> Number
          (define (move f ret)
            (cond
              [(> (ret location)
                  (ret target))
               (* -1 SPEED (f ANGLE))]
              [(< (ret location)
                  (ret target))
               (* SPEED (f ANGLE))]
              [else 0]))]
    (make-posn (+ (posn-x location) (move cos posn-x))
               (+ (posn-y location) (move sin posn-y)))))

; distance-to-next: Player -> [Maybe Number]
; interp. given a player, returns the square of the distance to the next
; waypoint. NOTE: the square is returned to avoid the imprecision of sqrt.
(check-expect (distance-to-next KOSI) 9)
(check-expect (distance-to-next MATTHIAS) 78025)
(check-expect (distance-to-next AMAL) false)
(define (distance-to-next player)
  (if (empty? (pl-waypoints player))
      false
      (+ (expt (- (posn-x (pl-location player)) 
                  (posn-x (first (pl-waypoints player))))
               2)
         (expt (- (posn-y (pl-location player)) 
                  (posn-y (first (pl-waypoints player)))) 
               2))))

; C. INCREMENTING SCORES
; ------------------------------------------------------------------------------
; increment-all-scores: HHServer -> HHServer
; interp. increments each players' score based on how many cupcakes he or she 
; is overlapping.
(define (increment-all-scores server)
  (local [(define (inner-net player)
            (increment-score player server))]
    (make-hhserver
     (map inner-net (hhserver-players server))
     (hhserver-cupcakes server)
     (hhserver-num server)
     (hhserver-started? server))))
(check-expect (increment-all-scores SAMPLE-SERVER)
              (make-hhserver
               (list
                (make-pl iworld1 (make-posn 50 50) (list (make-posn 50 53)) 13)
                (make-pl iworld2 
                         (make-posn 250 250) (list (make-posn 55 50)) 0)
                (make-pl iworld3 (make-posn 150 150) empty 0))
               (list (make-posn 30 30) (make-posn 40 40) (make-posn 50 50))
               3
               true))

; increment-score: Player HHServer -> Player
; interp. increments the player's score field based on how many cupcakes he or
; she is overlapping by counting how many are overlapped.
(define (increment-score player server)
  (make-pl
   (pl-world player)
   (pl-location player)
   (pl-waypoints player)
   (+ (pl-score player)
      (num-cc player server))))
(check-expect (increment-score KOSI SAMPLE-SERVER)
              (make-pl iworld1 (make-posn 50 50) (list (make-posn 50 53)) 13))
(check-expect (increment-score AMAL SAMPLE-SERVER)
              (make-pl iworld3 (make-posn 150 150) empty 0))
(check-expect (increment-score MATTHIAS SAMPLE-SERVER)
              (make-pl iworld2 (make-posn 250 250) 
                       (list (make-posn 55 50)) 0))

; num-cc: Player HHServer -> Number
; interp. returns the number of cupcakes that the given player overlaps.
(check-expect (num-cc KOSI SAMPLE-SERVER) 3)
(check-expect (num-cc MATTHIAS SAMPLE-SERVER) 0)
(check-expect (num-cc AMAL SAMPLE-SERVER) 0)
(define (num-cc player server)
  (local [(define location (pl-location player))
          (define (inner-net cupcake)
            (overlap? location cupcake))]
    (length (filter inner-net (hhserver-cupcakes server)))))

; overlap?: Posn Posn -> Boolean
; interp. checks if a player at the first position overlapping the center of a 
; cupcake at the second position.
; ASSUME: the player and other player are the same in dimensions.
(check-expect (overlap? (make-posn 0 0) (make-posn 2 2)) true)
(check-expect (overlap? (make-posn 10 10) (make-posn 20 20)) true)
(check-expect (overlap? (make-posn 10 10) (make-posn 40 40)) false)
(define (overlap? location target)
  (local [(define w (image-width PLAYER))
          (define h (image-height PLAYER))
          (define x-dist (abs (- (posn-x location)
                                 (posn-x target))))
          (define y-dist (abs (- (posn-y location)
                                 (posn-y target))))]
    (and (>= w y-dist) (>= h x-dist))))

; D. EATING CUPCAKES
; ------------------------------------------------------------------------------
; eat-all-cupcakes: HHServer -> HHServer
; interp. deletes all cupcakes which are overlapping any player.
(define (eat-all-cupcakes server)
  (local [(define players (hhserver-players server))
          (define (inner-net cupcake)
            (not (overlap-any? cupcake (extract-all-posns players))))]
    (make-hhserver
     players
     (filter inner-net (hhserver-cupcakes server))
     (hhserver-num server)
     (hhserver-started? server))))
(check-expect (eat-all-cupcakes SAMPLE-SERVER)
              (make-hhserver
               (list
                (make-pl iworld1 (make-posn 50 50) (list (make-posn 50 53)) 10)
                (make-pl iworld2 (make-posn 250 250) 
                         (list (make-posn 55 50)) 0)
                (make-pl iworld3 (make-posn 150 150) empty 0))
               empty
               3
               true))

; extract-all-posns: [List-of Player] -> [List-of Posn]
; interp. converts players into simple posns
(define (extract-all-posns players)
  (map pl-location players))
(check-expect (extract-all-posns PLAYERS)
              (list (make-posn 50 50) (make-posn 250 250) (make-posn 150 150)))

; overlap-any? Posn [List-of Posn] -> Boolean
; interp. checks if any of the players in the list overlap the given cupcake.
(define (overlap-any? cupcake all-players)
  (local [(define (inner-net player)
            (overlap? player cupcake))]
    (ormap inner-net all-players)))
(check-expect (overlap-any? (make-posn 5 5)
                            (list (make-posn 0 0) (make-posn 10 10))) true)
(check-expect (overlap-any? (make-posn 50 50)
                            (list (make-posn 0 0) (make-posn 10 10))) false)
(check-expect (overlap-any? (make-posn 10 50)
                            (list (make-posn 0 0) (make-posn 10 10))) false)

; E. TELLING THE CLIENTS TO WAIT
; ------------------------------------------------------------------------------
; wait-universe: HHServer -> UniverseBundle
; interp. sends a wait message to every universe, containing the number of
; additional players that are being awaited before the game can begin.
; Launches the game if that number is less than 1 (READ: 0)
(define (wait-universe server)
  (local [(define num (hhserver-num server))
          (define num-in (length (hhserver-players server)))
          (define num-wait (- num num-in))
          (define new-server
            (cond
              [(< num-wait 1) (launch-game server)]
              [else server]))]
    (make-bundle new-server
                 (mail-all-waits server)
                 empty)))
(check-expect (wait-universe UNFILLED-SERVER)
              (make-bundle
               UNFILLED-SERVER
               WAIT-MAIL
               empty))
(check-expect (wait-universe NOT-STARTED)
              (make-bundle
               STARTED
               (list (make-mail iworld1 (list 'wait 0)) 
                     (make-mail iworld2 (list 'wait 0)) 
                     (make-mail iworld3 (list 'wait 0)))
               empty))

; mail-all-waits: HHServer -> [List-of Mail]
; interp. creates a list of mail, containing 
(define (mail-all-waits server)
  (local [(define num (length (hhserver-players server)))
          (define all-worlds (arrange-all-worlds server num))]
    (map server->wait all-worlds)))
(check-expect (mail-all-waits UNFILLED-SERVER)
              (list (make-mail iworld1 (list 'wait 7)) 
                    (make-mail iworld2 (list 'wait 7)) 
                    (make-mail iworld3 (list 'wait 7))))
(check-expect (mail-all-waits NOT-STARTED)
              (list (make-mail iworld1 (list 'wait 0)) 
                    (make-mail iworld2 (list 'wait 0)) 
                    (make-mail iworld3 (list 'wait 0))))

; server->wait: HHServer -> Mail
; interp. sends a wait message to the first player in the given server
(define (server->wait server)
  (local [(define num (hhserver-num server))
          (define players (hhserver-players server))
          (define num-players (length players))
          (define this-player (first players))]
    (make-mail (pl-world this-player)
               (list 'wait (- num num-players)))))
(check-expect (server->wait SAMPLE-SERVER)
              (make-mail iworld1 (list 'wait 0)))
(check-expect (server->wait SAMPLE-SERVER-SWAPPED)
              (make-mail iworld2 (list 'wait 0)))
(check-expect (server->wait UNFILLED-SERVER)
              (make-mail iworld1 (list 'wait 7)))

; launch-game: HHServer -> HHServer
; interp. when waiting for 0 more players, flips the started? boolean in the
; universe state to indicate that the universe has started
(check-expect (launch-game NOT-STARTED) STARTED)
(define (launch-game server)
  (make-hhserver
   (hhserver-players server)
   (hhserver-cupcakes server)
   (hhserver-num server)
   true))

; F. COMBINING ALL THE ACTION AND SENDING IT OFF
; ------------------------------------------------------------------------------
; advance-universe: HHServer -> UniverseBundle
; interp. moves all players, increments their scores, removes all cupcakes that
; are being overlapped, and finally sends all the new states to each of the
; worlds.
(define (advance-universe server)
  (local [(define moved-avatars (move-all-avatars server))
          (define updated-scores (increment-all-scores moved-avatars))
          (define new-server (eat-all-cupcakes updated-scores))]
    (make-bundle new-server
                 (mail-to-all new-server)
                 empty)))
(check-within (advance-universe SAMPLE-SERVER)
              (make-bundle
               NEXT-TICK
               (list
                (make-mail iworld1 
                           (list 'world (list 50 53) empty 
                                 (list (list #i246.50 #i246.41) 
                                       (list 150 150)) (list (list 30 30))))
                (make-mail iworld2 
                           (list 'world (list #i246.50 #i246.41) 
                                 (list (list 55 50)) 
                                 (list (list 150 150) (list 50 53)) 
                                 (list (list 30 30))))
                (make-mail iworld3 (list 'world (list 150 150) empty 
                                         (list (list 50 53) 
                                               (list #i246.50 #i246.41)) 
                                         (list (list 30 30)))))
               empty) 1)

; mail-to-all: HHServer -> [List-of Mail]
; interp. mails the current world state to all players, from their perspective.
(define (mail-to-all server)
  (local [(define num (length (hhserver-players server)))
          (define all-worlds 
            (arrange-all-worlds server num))]
    (map server->mail all-worlds)))
(check-expect (mail-to-all SAMPLE-SERVER)
              (list
               (make-mail iworld1 (list 'world (list 50 50) (list (list 50 53)) 
                                        (list (list 250 250) (list 150 150)) 
                                        (list (list 30 30) (list 40 40) 
                                              (list 50 50))))
               (make-mail iworld2 (list 'world (list 250 250) 
                                        (list (list 55 50))
                                        (list (list 150 150) (list 50 50)) 
                                        (list (list 30 30) (list 40 40) 
                                              (list 50 50))))
               (make-mail iworld3 (list 'world (list 150 150) 
                                        empty 
                                        (list (list 50 50) (list 250 250)) 
                                        (list (list 30 30) (list 40 40) 
                                              (list 50 50))))))

; server->mail: HHServer -> Mail
; interp. converts a server into a mail message, assuming the first player in
; this list is the one which is meant to recieve the message.
(define (server->mail server)
  (local [(define this-player (first (hhserver-players server)))
          (define other-players (rest (hhserver-players server)))]
    (make-mail (pl-world this-player)
               (list 'world
                     (posn->list (pl-location this-player))
                     (posns->lists (pl-waypoints this-player))
                     (posns->lists (extract-all-posns other-players))
                     (posns->lists (hhserver-cupcakes server))))))
(check-expect (server->mail SAMPLE-SERVER)
              (make-mail iworld1 (list 'world (list 50 50) (list (list 50 53)) 
                                       (list (list 250 250) (list 150 150)) 
                                       (list (list 30 30) (list 40 40) 
                                             (list 50 50)))))

; arrange-all-worlds: HHServer Number -> [List-of HHServer]
; interp. given an HHServer and the number of players, creates an HHServer such
; that each player is at the front of the list exactly once.
(define (arrange-all-worlds server num)
  (cond
    [(zero? num) empty]
    [else
     (local [(define players (hhserver-players server))
             (define next-server (make-hhserver
                                  (swap-players players)
                                  (hhserver-cupcakes server)
                                  (hhserver-num server)
                                  (hhserver-started? server)))]
       (cons server
             (arrange-all-worlds next-server (sub1 num))))]))
(check-expect (equal? (first (hhserver-players 
                              (first (arrange-all-worlds SAMPLE-SERVER 3)))) 
                      KOSI) true)
(check-expect (equal? (first (hhserver-players 
                              (second (arrange-all-worlds SAMPLE-SERVER 3)))) 
                      MATTHIAS) true)
(check-expect (equal? (third (hhserver-players 
                              (second (arrange-all-worlds SAMPLE-SERVER 3)))) 
                      AMAL) false)

; swap-players: [List-of Players] -> [List-of Players]
; interp. puts the first player at the end of the list of players.
(check-expect (swap-players PLAYERS) SWAPPED-PLAYERS)
(define (swap-players players)
  (append (rest players) (list (first players))))

; posns->lists: [List-of Posn] -> [List-of [List-of Number]]
; interp. applies the posn->list function on an entire list of posns.
(check-expect (posns->lists POLIST) LOLIST)
(define (posns->lists posns)
  (map posn->list posns))

; posn->list: Posn -> [List-of Number]
; interp. given a posn, converts it to a list of two numbers such that the
; first number is the x-value and the second is the y-value of the posn.
(check-expect (posn->list POSN#1) LIST#1)
(check-expect (posn->list POSN#2) LIST#2)
(define (posn->list a-posn)
  (list (posn-x a-posn) (posn-y a-posn)))

; G. ENDING THE GAME
; ------------------------------------------------------------------------------
; end-universe: HHServer -> UniverseBundle
; interp. when there are no more cupcakes, sends all the universes whether they
; win or lose, and drops all the associated worlds. 
; ASSUME no two clients have the same number of cupcakes.
(define (end-universe server)
  (local [(define new-server (order-by-player-score server))]
    (make-bundle
     new-server 
     (mail-list new-server)
     empty)))
(check-expect (end-universe NO-CUPCAKE-SERVER)
              (make-bundle NO-CUPCAKE-SERVER
                           END-MAIL
                           empty))

; mail-list: HHServer -> [List-of Mail]
; interp. creates a list of mail, telling the first player in the list he has
; won, and the rest that they have lost.
(define (mail-list server)
  (local [(define winner (first (hhserver-players server)))
          (define the-rest (rest (hhserver-players server)))]
    (append (list (make-mail (pl-world winner) (list 'end true)))
            (map loser->end the-rest))))
(check-expect (mail-list SAMPLE-SERVER)
              (list (make-mail iworld1 (list 'end true)) 
                    (make-mail iworld2 (list 'end false)) 
                    (make-mail iworld3 (list 'end false))))

; loser->end: Player -> Mail
; interp. takes a single players and returns mail indicating that they have not
; won the game.
(check-expect (loser->end KOSI) (make-mail iworld1 (list 'end false)))
(check-expect (loser->end MATTHIAS) (make-mail iworld2 (list 'end false)))
(check-expect (loser->end AMAL) (make-mail iworld3 (list 'end false)))
(define (loser->end player)
  (make-mail (pl-world player) (list 'end false)))

; order-by-player-score: HHServer -> HHServer
; interp. sorts all the players in the universe by their score
(check-expect (order-by-player-score SAMPLE-SERVER) SAMPLE-SERVER)
(check-expect (order-by-player-score SAMPLE-SERVER-SWAPPED) SAMPLE-SERVER)
(define (order-by-player-score server)
  (make-hhserver
   (sort (hhserver-players server)
         (λ (x y) (> (pl-score x) (pl-score y))))
   (hhserver-cupcakes server)
   (hhserver-num server)
   (hhserver-started? server)))

; H. ADDING WAYPOINTS
; ------------------------------------------------------------------------------
; add-wp-to-player: [List-of Player] IWorld Posn -> [List-of Player]
; interp. adds the posn to the list of waypoints of the player with the matching
; IWorld.
; ASSUME a player with a matching IWorld exists in the list of players.
; (world location waypoints score)
(define (add-wp-to-player players world waypoint)
  (local [(define this-player (first players))]
    (cond
      [(iworld=? (pl-world this-player) world)
       (cons (make-pl
              (pl-world this-player)
              (pl-location this-player)
              (append (pl-waypoints this-player) (list waypoint))
              (pl-score this-player))
             (rest players))]
      [else 
       (cons this-player 
             (add-wp-to-player (rest players) world waypoint))])))
(check-expect (add-wp-to-player PLAYERS iworld3 (make-posn 100 100))
              (list
               (make-pl iworld1 (make-posn 50 50) (list (make-posn 50 53)) 10)
               (make-pl iworld2 (make-posn 250 250) (list (make-posn 55 50)) 0)
               (make-pl iworld3 (make-posn 150 150) 
                        (list (make-posn 100 100)) 0)))

; ------------------------------------------------------------------------------
; PART 10. DATA FOR TESTING
; ------------------------------------------------------------------------------
; A. CLIENT DATA FOR TESTING
; ------------------------------------------------------------------------------
; Different Server2Clients
(define BASIC-S2C (list 'wait 5))
(define ANOTHER-S2C (list 'world '(1 2) '((3 4) (5 6))
                          '((7 8) (9 10)) '((11 12) (13 14))))
(define AN-S2C (list 'world '(100 100) empty empty empty))
(define END-S2C (list 'end true))

; Different HHClients
(define BLANK-CLIENT 'none)
(define NUMERICAL-CLIENT 2)
(define STRUCTURE-CLIENT 
  (make-hhclient (make-posn 300 300)
                 (list (make-posn 150 150) (make-posn 450 150))
                 (list (make-posn 150 450) (make-posn 450 450))
                 (list (make-posn 550 450) (make-posn 450 550))))

; B. SERVER DATA FOR TESTING
; ------------------------------------------------------------------------------
; Different Players
(define KOSI (make-pl iworld1 (make-posn 50 50) 
                      (list (make-posn 50 53)) 10))
(define MATTHIAS (make-pl iworld2 
                          (make-posn 250 250) (list (make-posn 55 50)) 0))
(define AMAL (make-pl iworld3 (make-posn 150 150) empty 0))

; Different Lists of Players
(define PLAYERS (list KOSI MATTHIAS AMAL))
(define SWAPPED-PLAYERS (list MATTHIAS AMAL KOSI))

; Different HHServers
(define NOT-STARTED (make-hhserver PLAYERS empty 3 false))
(define STARTED (make-hhserver PLAYERS empty 3 true))
(define SAMPLE-SERVER (make-hhserver PLAYERS
                                     (list (make-posn 30 30)
                                           (make-posn 40 40)
                                           (make-posn 50 50))
                                     3
                                     true))
(define NEXT-TICK (make-hhserver
                   (list
                    (make-pl iworld1 (make-posn 50 53) empty 12)
                    (make-pl iworld2 (make-posn 246 246) 
                             (list (make-posn 55 50)) 0)
                    (make-pl iworld3 (make-posn 150 150) empty 0))
                   (list (make-posn 30 30))
                   3
                   true))
(define SAMPLE-SERVER-SWAPPED (make-hhserver SWAPPED-PLAYERS
                                             (list (make-posn 30 30)
                                                   (make-posn 40 40)
                                                   (make-posn 50 50))
                                             3
                                             true))
(define UNFILLED-SERVER (make-hhserver PLAYERS
                                       (list (make-posn 30 30)
                                             (make-posn 40 40)
                                             (make-posn 50 50))
                                       10
                                       false))
(define ANOTHER-UNFILLED-SERVER (make-hhserver (list KOSI)
                                               empty
                                               2
                                               false))
(define NO-CUPCAKE-SERVER (make-hhserver PLAYERS empty 3 true))

; Different Posns as Lists
(define LIST#1 '(10 10))
(define LIST#2 '(30 40))
(define LOLIST (list LIST#1 LIST#2))

; Different Posns
(define POSN#1 (make-posn 10 10))
(define POSN#2 (make-posn 30 40))
(define POLIST (list POSN#1 POSN#2))

; Various Client2Server and Mail
(define CLIENT2SERVER (list 'wp LIST#1))
(define NEXT-MAIL (list (make-mail iworld1 
                                   (list 'world (list 50 53) 
                                         empty 
                                         (list (list 246 246) (list 150 150)) 
                                         (list (list 30 30))))
                        (make-mail iworld2 
                                   (list 'world (list 246 246) 
                                         (list (list 55 50)) 
                                         (list (list 150 150) (list 50 53)) 
                                         (list (list 30 30))))
                        (make-mail iworld3 
                                   (list 'world (list 150 150) 
                                         empty 
                                         (list (list 50 53) (list 246 246)) 
                                         (list (list 30 30))))))
(define WAIT-MAIL (list (make-mail iworld1 (list 'wait 7)) 
                        (make-mail iworld2 (list 'wait 7)) 
                        (make-mail iworld3 (list 'wait 7))))
(define END-MAIL (list (make-mail iworld1 (list 'end true)) 
                       (make-mail iworld2 (list 'end false)) 
                       (make-mail iworld3 (list 'end false))))