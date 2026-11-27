group = "dev.btkit"
version = "1.0"

buildscript {
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.3.1")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "dev.btkit"

    compileSdk = 37

    defaultConfig {
        minSdk = 33
        consumerProguardFiles("consumer-rules.pro")

        aarMetadata {
            minCompileSdk = 33
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
