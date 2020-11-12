port module Main exposing (..)

import Array exposing (Array)
import Array.Extra
import Browser
import Html exposing (Html, button, div, input, text, time)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput)
import Json.Decode as Decode
import Json.Encode as Encode



--TODO: days to array, expose less in header, save and load, add dates on clear.


type alias TimeInMinutes =
    Int


invalidTimeString : String
invalidTimeString =
    "--:--"


{-| output is in the format hh:mm, where mm
can be 00 to 59 and hh can be 00 to 99. if the int cannot
get converted to this format --:-- is returned.
-}
minutesToString : TimeInMinutes -> String
minutesToString timeInMinutes =
    let
        minMinutes =
            0

        maxMinutes =
            99 * 60 + 59
    in
    if (timeInMinutes > maxMinutes) || (timeInMinutes < minMinutes) then
        invalidTimeString

    else
        let
            hours =
                timeInMinutes // 60

            remainingMinutes =
                remainderBy 60 timeInMinutes

            --we have already checked if int has valid values.
            intToTwoDigitString : Int -> String
            intToTwoDigitString int =
                if int < 10 then
                    "0" ++ String.fromInt int

                else
                    String.fromInt int
        in
        intToTwoDigitString hours ++ ":" ++ intToTwoDigitString remainingMinutes


{-| convert format hh:mm to int in minutes. hh can be from 00 to 99 and minute from
00 to 59. all other formats return a nothing value.
-}
stringToMinutes : String -> Maybe TimeInMinutes
stringToMinutes string =
    let
        maybeHours =
            String.toInt (String.slice 0 2 string)

        separatorIsCorrect =
            String.slice 2 3 string == ":"

        maybeMinutes =
            String.toInt (String.slice 3 5 string)
    in
    case ( maybeHours, separatorIsCorrect, maybeMinutes ) of
        ( Just hours, True, Just minutes ) ->
            if (hours < 0) || (hours > 99) || (minutes < 0) || (minutes > 59) then
                Nothing

            else
                Just (hours * 60 + minutes)

        _ ->
            Nothing


taskTime : Task -> Maybe TimeInMinutes
taskTime task =
    case ( task.startTime, task.stopTime ) of
        ( Just startTime, Just stopTime ) ->
            Just (stopTime - startTime)

        _ ->
            Nothing


dailyWorktime : Day -> Maybe TimeInMinutes
dailyWorktime day =
    let
        maybeAdd : Maybe TimeInMinutes -> Maybe TimeInMinutes -> Maybe TimeInMinutes
        maybeAdd first second =
            case ( first, second ) of
                ( Just firstTime, Just secondTime ) ->
                    Just (firstTime + secondTime)

                _ ->
                    Nothing
    in
    day.tasks
        |> Array.map taskTime
        |> Array.foldl maybeAdd (Just 0)


type alias DayIndex =
    Int


type alias TaskIndex =
    Int


type alias Task =
    { project : String
    , comment : String
    , startTime : Maybe TimeInMinutes
    , stopTime : Maybe TimeInMinutes
    }


emptyTask : Maybe TimeInMinutes -> Task
emptyTask startTime =
    { project = ""
    , comment = ""
    , startTime = startTime
    , stopTime = Nothing
    }


viewTask : DayIndex -> TaskIndex -> Task -> Html Msg
viewTask dayIndex taskIndex task =
    div [ class "task" ]
        [ div [ class "top_row" ]
            [ input
                [ class "project"
                , type_ "text"
                , value task.project
                , onInput (SetProject dayIndex taskIndex)
                ]
                []
            , input
                [ class "comment"
                , type_ "text"
                , value task.comment
                , onInput (SetComment dayIndex taskIndex)
                ]
                []
            , button
                [ class "close_button"
                , onClick (RemoveTask dayIndex taskIndex)
                ]
                [ text "x" ]
            ]
        , div [ class "bottom_row" ]
            [ input
                [ class "start_time"
                , type_ "time"
                , case task.startTime of
                    Just time ->
                        value (minutesToString time)

                    Nothing ->
                        value invalidTimeString
                , onInput (SetStartTime dayIndex taskIndex)
                ]
                []
            , input
                [ class "stop_time"
                , type_ "time"
                , case task.stopTime of
                    Just time ->
                        value (minutesToString time)

                    Nothing ->
                        value invalidTimeString
                , onInput (SetStopTime dayIndex taskIndex)
                ]
                []
            ]
        ]


type alias Day =
    { tasks : Array Task
    }


dayIndexToString : DayIndex -> String
dayIndexToString dayIndex =
    case dayIndex of
        0 ->
            "monday"

        1 ->
            "tuesday"

        2 ->
            "wednesday"

        3 ->
            "thursday"

        4 ->
            "friday"

        _ ->
            "unknown day"


viewDay : Maybe TimeInMinutes -> DayIndex -> Day -> Html Msg
viewDay requiredMinutes dayIndex day =
    div [ class "day" ]
        [ text (dayIndexToString dayIndex)
        , div [ class "tasks" ] (Array.toList (Array.indexedMap (\taskIndex task -> viewTask dayIndex taskIndex task) day.tasks))
        , case requiredMinutes of
            Just minutes ->
                if minutes > 0 then
                    time [ class "required_minutes_red" ] [ text (minutesToString minutes) ]

                else
                    time [ class "required_minutes_green" ] [ text (minutesToString -minutes) ]

            Nothing ->
                time [ class "required_minutes_white" ] [ text invalidTimeString ]
        , button [ onClick (AddTask dayIndex) ] [ text "add task" ]
        ]


main : Program Encode.Value Model Msg
main =
    Browser.element
        { init = init
        , view = view
        , update = updateWithStorage
        , subscriptions = \_ -> Sub.none
        }


type alias Model =
    { days : Array Day }


init : Encode.Value -> ( Model, Cmd Msg )
init flags =
    ( case Decode.decodeValue decoder flags of
        Ok model ->
            model

        Err _ ->
            { days = Array.repeat 5 { tasks = Array.empty } }
    , Cmd.none
    )


view : Model -> Html Msg
view model =
    let
        requiredDailyWorkTime =
            8 * 60

        addRequiredMinutesToArray : Day -> Array (Maybe TimeInMinutes) -> Array (Maybe TimeInMinutes)
        addRequiredMinutesToArray day array =
            if Array.isEmpty day.tasks then
                case Array.get (Array.length array - 1) array of
                    Nothing ->
                        Array.push (Just 0) array

                    Just accumulatedTime ->
                        Array.push accumulatedTime array

            else
                case ( dailyWorktime day, Array.get (Array.length array - 1) array ) of
                    ( Just workTime, Nothing ) ->
                        Array.push (Just (requiredDailyWorkTime - workTime)) array

                    ( Just workTime, Just (Just accumulatedTime) ) ->
                        Array.push (Just ((requiredDailyWorkTime - workTime) + accumulatedTime)) array

                    _ ->
                        Array.push Nothing array

        requiredMinutes : Array (Maybe TimeInMinutes)
        requiredMinutes =
            Array.foldl addRequiredMinutesToArray Array.empty model.days

        daysData : Array ( Maybe TimeInMinutes, Day )
        daysData =
            Array.Extra.zip requiredMinutes model.days

        dayDataToHtml : Int -> ( Maybe TimeInMinutes, Day ) -> Html Msg
        dayDataToHtml dayIndex dayData =
            viewDay (Tuple.first dayData) dayIndex (Tuple.second dayData)
    in
    div [ class "week" ]
        (Array.toList
            (Array.indexedMap dayDataToHtml daysData)
        )


type Msg
    = AddTask DayIndex
    | RemoveTask DayIndex TaskIndex
    | SetProject DayIndex TaskIndex String
    | SetComment DayIndex TaskIndex String
    | SetStartTime DayIndex TaskIndex String
    | SetStopTime DayIndex TaskIndex String


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        AddTask dayIndex ->
            let
                addTask : Day -> Maybe TimeInMinutes -> Day
                addTask day startTime =
                    { day | tasks = Array.push (emptyTask startTime) day.tasks }

                updateDay : Day -> Day
                updateDay day =
                    case Array.get (Array.length day.tasks - 1) day.tasks of
                        Just previousTask ->
                            addTask day previousTask.stopTime

                        Nothing ->
                            addTask day Maybe.Nothing
            in
            ( { model | days = Array.Extra.update dayIndex updateDay model.days }
            , Cmd.none
            )

        RemoveTask dayIndex taskIndex ->
            let
                removeTask : Day -> Day
                removeTask day =
                    { day | tasks = Array.Extra.removeAt taskIndex day.tasks }
            in
            ( { model | days = Array.Extra.update dayIndex removeTask model.days }
            , Cmd.none
            )

        SetProject dayIndex taskIndex project ->
            let
                setProject : Task -> Task
                setProject task =
                    { task | project = project }

                updateDay : Day -> Day
                updateDay day =
                    { day | tasks = Array.Extra.update taskIndex setProject day.tasks }
            in
            ( { model | days = Array.Extra.update dayIndex updateDay model.days }
            , Cmd.none
            )

        SetComment dayIndex taskIndex comment ->
            let
                setComment : Task -> Task
                setComment task =
                    { task | comment = comment }

                updateDay : Day -> Day
                updateDay day =
                    { day | tasks = Array.Extra.update taskIndex setComment day.tasks }
            in
            ( { model | days = Array.Extra.update dayIndex updateDay model.days }
            , Cmd.none
            )

        SetStartTime dayIndex taskIndex startTime ->
            let
                setStartTime : Task -> Task
                setStartTime task =
                    { task | startTime = stringToMinutes startTime }

                updateTask : Task -> Array Task
                updateTask task =
                    adaptToLunch (setStartTime task)

                updateDay : Day -> Day
                updateDay day =
                    { day | tasks = replaceAt taskIndex updateTask day.tasks }
            in
            ( { model | days = Array.Extra.update dayIndex updateDay model.days }
            , Cmd.none
            )

        SetStopTime dayIndex taskIndex stopTime ->
            let
                setStopTime : Task -> Task
                setStopTime task =
                    { task | stopTime = stringToMinutes stopTime }

                updateTask : Task -> Array Task
                updateTask task =
                    adaptToLunch (setStopTime task)

                updateDay : Day -> Day
                updateDay day =
                    { day | tasks = replaceAt taskIndex updateTask day.tasks }
            in
            ( { model | days = Array.Extra.update dayIndex updateDay model.days }
            , Cmd.none
            )


{-| take an array and replace element at given index with zero or more elements defined by a
replacement function that takes that element as input.
-}
replaceAt : Int -> (a -> Array a) -> Array a -> Array a
replaceAt index replacement array =
    let
        left =
            Array.slice 0 index array

        right =
            Array.slice (index + 1) (Array.length array) array

        maybeElement =
            Array.get index array
    in
    case maybeElement of
        Just element ->
            Array.append left (Array.append (replacement element) right)

        Nothing ->
            array


adaptToLunch : Task -> Array Task
adaptToLunch task =
    let
        startLunch =
            12 * 60 + 30

        endLunch =
            13 * 60
    in
    case ( task.startTime, task.stopTime ) of
        ( Just startTime, Just stopTime ) ->
            let
                startTimeBeforeLunch =
                    startTime < startLunch

                startTimeInLunch =
                    (startTime >= startLunch) && (startTime < endLunch)

                stopTimeInLunch =
                    (stopTime > startLunch) && (stopTime <= endLunch)

                stopTimeAfterLunch =
                    stopTime > endLunch

                endsInLunch =
                    startTimeBeforeLunch && stopTimeInLunch

                inLunch =
                    startTimeInLunch && stopTimeInLunch

                startsInLunch =
                    startTimeInLunch && stopTimeAfterLunch

                envelopsLunch =
                    startTimeBeforeLunch && stopTimeAfterLunch
            in
            if endsInLunch then
                --crop stop time.
                Array.fromList [ { task | stopTime = Just startLunch } ]

            else if startsInLunch then
                --crop start time.
                Array.fromList [ { task | startTime = Just endLunch } ]

            else if inLunch then
                --remove task.
                Array.empty

            else if envelopsLunch then
                --split task in part before and after lunch.
                Array.fromList [ { task | stopTime = Just startLunch }, { task | startTime = Just endLunch } ]

            else
                --other cases we do not need to change anything.
                Array.fromList [ task ]

        _ ->
            Array.fromList [ task ]


port setStorage : Encode.Value -> Cmd msg


updateWithStorage : Msg -> Model -> ( Model, Cmd Msg )
updateWithStorage msg oldModel =
    let
        ( newModel, cmds ) =
            update msg oldModel
    in
    ( newModel
    , Cmd.batch [ setStorage (encode newModel), cmds ]
    )


encode : Model -> Encode.Value
encode model =
    Encode.object
        [ ( "days", Encode.array encodeDay model.days ) ]


encodeDay : Day -> Encode.Value
encodeDay day =
    Encode.object
        [ ( "tasks", Encode.array encodeTask day.tasks )
        ]


encodeTask : Task -> Encode.Value
encodeTask task =
    let
        startTime =
            case task.startTime of
                Just minutes ->
                    [ ( "startTime", Encode.int minutes ) ]

                Nothing ->
                    []

        stopTime =
            case task.stopTime of
                Just minutes ->
                    [ ( "stopTime", Encode.int minutes ) ]

                Nothing ->
                    []
    in
    Encode.object
        (List.concat
            [ [ ( "project", Encode.string task.project )
              , ( "comment", Encode.string task.comment )
              ]
            , startTime
            , stopTime
            ]
        )


decoder : Decode.Decoder Model
decoder =
    Decode.map Model
        (Decode.field "days" (Decode.array dayDecoder))


dayDecoder : Decode.Decoder Day
dayDecoder =
    Decode.map Day
        (Decode.field "tasks" (Decode.array taskDecoder))


taskDecoder : Decode.Decoder Task
taskDecoder =
    Decode.map4 Task
        (Decode.field "project" Decode.string)
        (Decode.field "comment" Decode.string)
        (Decode.maybe (Decode.field "startTime" Decode.int))
        (Decode.maybe (Decode.field "stopTime" Decode.int))
