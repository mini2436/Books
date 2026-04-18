plugins {
    kotlin("jvm")
    kotlin("plugin.spring")
}

dependencies {
    implementation(platform("org.springframework.boot:spring-boot-dependencies:3.5.0"))
    implementation(project(":plugin-api"))
    implementation("org.springframework:spring-context")
}

kotlin {
    jvmToolchain(21)
}
