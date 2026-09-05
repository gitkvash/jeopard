package ge.jeopard.backend.config;

import org.springframework.beans.factory.annotation.Value;
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
 * <p>Pending opens are dropped on shutdown rather than waited for, since by the
 * time the process comes back the reading time is long past and the host's own
 * button is the way out.
 *
 * <p>The pool is shared by every room. One task is a state flip and a
 * broadcast, so a thread is held for milliseconds -- but the threads are the
 * only thing standing between rooms here: a task that has to wait for a game
 * row held by a slow host action occupies its thread while it waits, and with
 * too few threads that is one room's timer delaying another's. Four is enough
 * that a couple of stalled tasks still leave the rest of the house running, and
 * {@code JEOPARD_BUZZ_TIMER_THREADS} raises it for a deployment running more
 * rooms than that at once.
 */
@Configuration
public class SchedulingConfig {

    /** Bean name of the scheduler that opens automatic buzzers. */
    public static final String BUZZ_TIMER = "buzzTimerScheduler";

    private final int poolSize;

    SchedulingConfig(@Value("${jeopard.buzz-timer.threads:4}") int poolSize) {
        this.poolSize = poolSize;
    }

    /**
     * Named, and injected by name: the STOMP broker brings a TaskScheduler of
     * its own, so an unqualified one of these is two beans and no context.
     */
    @Bean(BUZZ_TIMER)
    TaskScheduler buzzTimerScheduler() {
        ThreadPoolTaskScheduler scheduler = new ThreadPoolTaskScheduler();
        scheduler.setPoolSize(poolSize);
        scheduler.setThreadNamePrefix("buzz-timer-");
        scheduler.setWaitForTasksToCompleteOnShutdown(false);
        return scheduler;
    }
}
