package com.privatereader.common

import java.sql.Timestamp
import java.time.Instant

fun Instant.toSqlTimestamp(): Timestamp = Timestamp.from(this)

