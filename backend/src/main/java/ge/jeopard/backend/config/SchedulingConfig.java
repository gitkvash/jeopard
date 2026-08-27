package ge.jeopard.backend.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.TaskScheduler;
import org.springframework.scheduling.concurrent.ThreadPoolTaskScheduler;

/**
 * The thread that opens a buzzer nobody pressed.
 *
 * <p>Declared here rather than relying on {@code @EnableScheduling}: there are
 * no cron methods in this application, only one-shot work booked at a deadline
 * when a clue goes up, and a bean that is obviously present beats one that
 * appears by auto-configuration.
 *
 * <p>Two threads is plenty -- each task holds the game row for the moment it
 * takes to flip a state and broadcast -- and pending opens are dropped on
 * shutdown rather than waited for, since by the time the process comes back the
 * reading time is long past and the host's own button is the way out.
 */
@Configuration
public class SchedulingConfig {

    /** Bean name of the scheduler that opens automatic buzzers. */
    public static final String BUZZ_TIMER = "buzzTimerScheduler";

    /**
     * Named, and injected by name: the STOMP broker brings a TaskScheduler of
     * its own, so an unqualified one of these is two beans and no context.
     */
    @Bean(BUZZ_TIMER)
    TaskScheduler buzzTimerScheduler() {
        ThreadPoolTaskScheduler scheduler = new ThreadPoolTaskScheduler();
        scheduler.setPoolSize(2);
        scheduler.setThreadNamePrefix("buzz-timer-");
        scheduler.setWaitForTasksToCompleteOnShutdown(false);
        return scheduler;
    }
}
