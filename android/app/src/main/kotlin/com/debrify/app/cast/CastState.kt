package com.debrify.app.cast

enum class DebrifyCastState(val wireValue: String) {
    DISCONNECTED("disconnected"),
    CONNECTING("connecting"),
    CONNECTED("connected"),
    PLAYING("playing"),
    PAUSED("paused"),
    ENDED("ended"),
    ERROR("error"),
}
