package com.papyrus.reader;

import androidx.test.platform.app.InstrumentationRegistry;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.junit.runners.Parameterized;
import pl.leancode.patrol.PatrolJUnitRunner;

@RunWith(Parameterized.class)
public class MainActivityTest {
    private final String testName;

    public MainActivityTest(String testName) {
        this.testName = testName;
    }

    private static PatrolJUnitRunner runner() {
        return (PatrolJUnitRunner) InstrumentationRegistry.getInstrumentation();
    }

    @Parameterized.Parameters(name = "{0}")
    public static Object[] testCases() {
        PatrolJUnitRunner runner = runner();
        runner.setUp(MainActivity.class);
        runner.waitForPatrolAppService();
        return runner.listDartTests();
    }

    @Test
    public void runJourney() {
        runner().runDartTest(testName);
    }
}
