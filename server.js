const express = require('express');
const cors = require('cors');
const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());

// Data storage
const jobs = new Map(); // jobId -> { receiver, serverId, timestamp, status, petsCount }
const receivers = new Map(); // receiver -> { jobId, serverId, timestamp, status, petsCount, maxPets }
const senders = new Map(); // sender -> { status, targetReceiver, timestamp }
const tradeQueue = []; // Trade queue
const serverCache = new Map(); // Server cache

// Constants
const MAX_PETS_PER_ACCOUNT = 55; // Maximum pets per account
const TRADE_TIMEOUT = 5 * 60 * 1000; // 5 minutes for trade

// Clean expired records (older than 5 minutes)
setInterval(() => {
    const now = Date.now();
    const fiveMinutes = 5 * 60 * 1000;
    
    // Clean jobs
    for (const [jobId, job] of jobs.entries()) {
        if (now - job.timestamp > fiveMinutes) {
            jobs.delete(jobId);
            console.log(`Removed expired job: ${jobId}`);
        }
    }
    
    // Clean receivers
    for (const [receiver, data] of receivers.entries()) {
        if (now - data.timestamp > fiveMinutes) {
            receivers.delete(receiver);
            console.log(`Removed expired receiver: ${receiver}`);
        }
    }
    
    // Clean senders
    for (const [sender, data] of senders.entries()) {
        if (now - data.timestamp > fiveMinutes) {
            senders.delete(sender);
            console.log(`Removed expired sender: ${sender}`);
        }
    }
    
    // Clean queue
    tradeQueue.splice(0, tradeQueue.length);
}, 60000); // Check every minute

// Function to get normal server (without Roblox API)
function getNormalServer() {
    return {
        id: "normal-server",
        ping: 50,
        fps: 60,
        players: 0,
        type: "normal"
    };
}

// Function to check VIP server (only one player)
function isVipServer(players) {
    return players.length === 1;
}

// API Routes

// 1. Receiver registers their job
app.post('/api/register-job', (req, res) => {
    const { receiver, jobId, serverId, petsCount = 0, maxPets = MAX_PETS_PER_ACCOUNT } = req.body;
    
    if (!receiver || !jobId || !serverId) {
        return res.status(400).json({
            success: false,
            message: 'receiver, jobId and serverId are required'
        });
    }
    
    // Check receiver status
    let status = 'waiting';
    if (petsCount >= maxPets) {
        status = 'completed';
    }
    
    // Save job
    jobs.set(jobId, {
        receiver,
        serverId,
        timestamp: Date.now(),
        status,
        petsCount,
        maxPets
    });
    
    // Save receiver information
    receivers.set(receiver, {
        jobId,
        serverId,
        timestamp: Date.now(),
        status,
        petsCount,
        maxPets
    });
    
    console.log(`Registered job: ${jobId} for ${receiver} on server ${serverId} (status: ${status})`);
    
    res.json({
        success: true,
        message: 'Job registered',
        jobId,
        receiver,
        serverId,
        status,
        petsCount,
        maxPets
    });
});

// 2. Receiver updates their status
app.post('/api/update-receiver', (req, res) => {
    const { receiver, serverId, petsCount = 0, maxPets = MAX_PETS_PER_ACCOUNT } = req.body;
    
    if (!receiver || !serverId) {
        return res.status(400).json({
            success: false,
            message: 'receiver and serverId are required'
        });
    }
    
    // Check receiver status
    let status = 'waiting';
    if (petsCount >= maxPets) {
        status = 'completed';
    }
    
    // Update receiver information
    receivers.set(receiver, {
        jobId: receivers.get(receiver)?.jobId || null,
        serverId,
        timestamp: Date.now(),
        status,
        petsCount,
        maxPets
    });
    
    console.log(`Updated receiver status: ${receiver} on server ${serverId} (status: ${status})`);
    
    res.json({
        success: true,
        message: 'Status updated',
        receiver,
        serverId,
        status,
        petsCount,
        maxPets
    });
});

// 3. Sender checks available receivers
app.get('/api/check-receivers', (req, res) => {
    const { usernames } = req.query;
    
    if (!usernames) {
        return res.status(400).json({
            success: false,
            message: 'usernames parameter is required (comma-separated list)'
        });
    }
    
    const usernameList = usernames.split(',').map(name => name.trim());
    const availableReceivers = [];
    
    for (const username of usernameList) {
        const receiverData = receivers.get(username);
        if (receiverData && receiverData.status === 'waiting') {
            availableReceivers.push({
                username,
                serverId: receiverData.serverId,
                jobId: receiverData.jobId,
                timestamp: receiverData.timestamp,
                status: receiverData.status,
                petsCount: receiverData.petsCount,
                maxPets: receiverData.maxPets
            });
        }
    }
    
    res.json({
        success: true,
        availableReceivers,
        total: availableReceivers.length
    });
});

// 4. Sender requests normal server for trade
app.post('/api/request-trade-server', async (req, res) => {
    const { sender, targetReceiver } = req.body;
    
    if (!sender || !targetReceiver) {
        return res.status(400).json({
            success: false,
            message: 'sender and targetReceiver are required'
        });
    }
    
    // Check if receiver is available
    const receiverData = receivers.get(targetReceiver);
    if (!receiverData || receiverData.status !== 'waiting') {
        return res.status(400).json({
            success: false,
            message: 'Receiver is not available for trade'
        });
    }
    
    // Get normal server
    const normalServer = getNormalServer();
    
    // Register sender
    senders.set(sender, {
        status: 'trading',
        targetReceiver,
        timestamp: Date.now(),
        serverId: normalServer.id
    });
    
    // Add to trade queue
    tradeQueue.push({
        sender,
        receiver: targetReceiver,
        serverId: normalServer.id,
        timestamp: Date.now()
    });
    
    console.log(`Normal server requested for trade: ${sender} -> ${targetReceiver}`);
    
    res.json({
        success: true,
        message: 'Normal server for trade is ready',
        server: {
            id: normalServer.id,
            ping: normalServer.ping,
            fps: normalServer.fps,
            players: normalServer.players,
            type: normalServer.type
        },
        tradeInfo: {
            sender,
            receiver: targetReceiver,
            queuePosition: tradeQueue.length
        }
    });
});

// 5. Sender marks trade as completed
app.post('/api/complete-trade', (req, res) => {
    const { sender, receiver, success = true } = req.body;
    
    if (!sender || !receiver) {
        return res.status(400).json({
            success: false,
            message: 'sender and receiver are required'
        });
    }
    
    // Remove sender from list
    senders.delete(sender);
    
    // Remove from trade queue
    const tradeIndex = tradeQueue.findIndex(trade => 
        trade.sender === sender && trade.receiver === receiver
    );
    if (tradeIndex !== -1) {
        tradeQueue.splice(tradeIndex, 1);
    }
    
    console.log(`Trade completed: ${sender} -> ${receiver} (success: ${success})`);
    
    res.json({
        success: true,
        message: 'Trade marked as completed',
        sender,
        receiver,
        success
    });
});

// 6. Get trade queue information
app.get('/api/trade-queue', (req, res) => {
    res.json({
        success: true,
        queue: tradeQueue,
        total: tradeQueue.length
    });
});

// 7. Get statistics
app.get('/api/stats', (req, res) => {
    const waitingReceivers = Array.from(receivers.values()).filter(r => r.status === 'waiting').length;
    const completedReceivers = Array.from(receivers.values()).filter(r => r.status === 'completed').length;
    const activeSenders = Array.from(senders.values()).filter(s => s.status === 'trading').length;
    
    res.json({
        success: true,
        stats: {
            activeJobs: jobs.size,
            waitingReceivers,
            completedReceivers,
            activeSenders,
            tradeQueueLength: tradeQueue.length,
            serverTime: new Date().toISOString()
        }
    });
});

// 8. Get all active receivers
app.get('/api/receivers', (req, res) => {
    const receiversList = [];
    for (const [username, data] of receivers.entries()) {
        receiversList.push({
            username,
            ...data
        });
    }
    
    res.json({
        success: true,
        receivers: receiversList
    });
});

// 9. Get all active senders
app.get('/api/senders', (req, res) => {
    const sendersList = [];
    for (const [username, data] of senders.entries()) {
        sendersList.push({
            username,
            ...data
        });
    }
    
    res.json({
        success: true,
        senders: sendersList
    });
});

// 10. Get normal server information
app.get('/api/normal-server', (req, res) => {
    const normalServer = getNormalServer();
    
    res.json({
        success: true,
        server: normalServer,
        message: 'Normal server is ready to use'
    });
});

// Start server
app.listen(PORT, () => {
    console.log(`Server is running on port ${PORT}`);
    console.log(`API available at: http://localhost:${PORT}`);
});

module.exports = app;