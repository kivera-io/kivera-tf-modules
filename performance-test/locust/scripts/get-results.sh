#!/bin/bash
set -e

echo -e "\n############################\n"

echo -e "Link: http://${LEADER_USERNAME}:${LEADER_PASSWORD}@${LEADER_ADDRESS}\n"
echo "Endpoint: http://${LEADER_ADDRESS}"
echo "Username: ${LEADER_USERNAME}"
echo "Password: ${LEADER_PASSWORD}"

time=300

echo -e "\nWaiting for leader to become ready...\n"
while true; do
    status_code=$(curl -s -o /dev/null -w "%{http_code}" -u ${LEADER_USERNAME}:${LEADER_PASSWORD} http://${LEADER_ADDRESS} || :)
    [[ "$status_code" == "000" ]] && status_code="503"
    if [[ $GITHUB_ACTIONS != true ]]; then
        echo -e "\e[1A\e[KStatusCode: $status_code, Timeout: $time"
    elif [[ $(($time % 15)) == 0 ]]; then
        echo -e "StatusCode: $status_code, Timeout: $time"
    fi
    [[ "$status_code" == "200" ]] && break;
    [[ $time == 0 ]] && echo "Testing timed out" && exit;
    ((time-=1)); sleep 1;
done

echo -e "\n############################"

run_time=${LOCUST_RUN_TIME::-1}
time=$(((run_time * 60) + 300))

echo -e "\nWaiting for tests to finish...\n"
while true; do
    resp=$(curl -su ${LEADER_USERNAME}:${LEADER_PASSWORD} http://${LEADER_ADDRESS}/stats/requests || echo {})
    state=$(jq -r '.state // "deploying"' <<< "$resp")
    workers=$(jq -r '.workers // [] | length' <<< "$resp")
    users=$(jq -r '.user_count // 0' <<< "$resp")
    rps=$(jq -r '.total_rps // 0' <<< "$resp")
    if [[ $state == "stopping" ]] || [[ $state == "stopped" ]]; then
        echo "Retrieving results"
        echo "Results in ${RESULTS_DIR}/"
        curl -su ${LEADER_USERNAME}:${LEADER_PASSWORD} http://${LEADER_ADDRESS}/stats/requests/csv > "${RESULTS_DIR}/stats.csv"
        curl -su ${LEADER_USERNAME}:${LEADER_PASSWORD} http://${LEADER_ADDRESS}/stats/report?download=1 > "${RESULTS_DIR}/report.html"
        curl -su ${LEADER_USERNAME}:${LEADER_PASSWORD} http://${LEADER_ADDRESS}/stats/failures/csv > "${RESULTS_DIR}/failures.csv"
        curl -su ${LEADER_USERNAME}:${LEADER_PASSWORD} http://${LEADER_ADDRESS}/exceptions/csv > "${RESULTS_DIR}/exceptions.csv"
        curl -su ${LEADER_USERNAME}:${LEADER_PASSWORD} http://${LEADER_ADDRESS}/exceptions/csv > "${RESULTS_DIR}/exceptions.csv"
        break
    elif [[ $time == 0 ]]; then
        echo "Testing timed out"
        break
    else
        if [[ $GITHUB_ACTIONS != true ]]; then
            echo -e "\e[1A\e[KState: $state, Workers: $workers, Users: $users, RPS: $rps, Timeout: $time"
        elif [[ $(($time % 15)) == 0 ]]; then
            echo -e "State: $state, Workers: $workers, Users: $users, RPS: $rps, Timeout: $time"
        fi
        if [[ $state == "spawning" ]] || [[ $state == "running" ]]; then
            echo $resp > "${RESULTS_DIR}/stats/${EPOCHSECONDS}.json"
        fi
    fi
    ((time-=1)); sleep 1;
done

echo -e "\n############################\n"
